local cjson = require("cjson")
local http = require("resty.http")
local resolver = require ("resty.dns.resolver")
local ngx = ngx

local token = os.getenv("GOCACHE_DISCOVERY_TOKEN")
local discovery_host  = os.getenv("GOCACHE_DISCOVERY_HOSTNAME")

if not discovery_host or discovery_host == "" then 
   discovery_host = "api-inventory.gocache.com.br"
end

local max_requests_store  = os.getenv("GOCACHE_DISCOVERY_MAX_REQUESTS_STORED")
if not tonumber(max_requests_store) then 
   max_requests_store = 50
end

local requests_retention_seconds  = os.getenv("GOCACHE_DISCOVERY_REQUEST_RETENTION_SECONDS")
if not tonumber(requests_retention_seconds) then 
   requests_retention_seconds = 60
end

local resolver_nameservers  = os.getenv("GOCACHE_DISCOVERY_DNS_NAMESERVERS")
if not resolver_nameservers or resolver_nameservers == "" then 
   resolver_nameservers = "8.8.8.8, 8.8.8.9"
end

local gcshared = ngx.shared.gocache

local inventory_max_body_size = 2048

local accepted_request_content_types = {
    "application/json",
    "application/x%-www%-form%-urlencoded",
    "text/plain"
}

local accepted_response_content_types = {
   "application/json",
   "application/xml",
   "text/xml"
}

local ignore_headers = {
    ["a-im"]=true,
    ["accept"]=true,
    ["accept-charset"]=true,
    ["accept-datetime"]=true,
    ["accept-encoding"]=true,
    ["accept-language"]=true,
    ["access-control-request-method"]=true,
    ["access-control-request-headers"]=true,
    ["cache-control"]=true,
    ["connection"]=true,
    ["content-encoding"]=true,
    ["content-length"]=true,
    ["content-md5"]=true,
    ["content-type"]=true,
    ["cookie"]=true,
    ["date"]=true,
    ["expect"]=true,
    ["forwarded"]=true,
    ["from"]=true,
    ["host"]=true,
    ["http2-settings"]=true,
    ["if-match"]=true,
    ["if-modified-since"]=true,
    ["if-none-match"]=true,
    ["if-range"]=true,
    ["if-unmodified-since"]=true,
    ["max-forwards"]=true,
    ["origin"]=true,
    ["pragma"]=true,
    ["prefer"]=true,
    ["proxy-authorization"]=true,
    ["range"]=true,
    ["referer"]=true,
    ["sec-fetch-dest"]=true,
    ["sec-fetch-mode"]=true,
    ["sec-fetch-site"]=true,
    ["sec-fetch-user"]=true,
    ["te"]=true,
    ["trailer"]=true,
    ["transfer-encoding"]=true,
    ["user-agent"]=true,
    ["upgrade"]=true,
    ["via"]=true,
    ["warning"]=true,
    ["upgrade-insecure-requests"]=true,
    ["x-requested-with"]=true,
    ["dnt"]=true,
    ["x-forwarded-for"]=true,
    ["x-forwarded-host"]=true,
    ["x-forwarded-proto"]=true,
    ["front-end-https"]=true,
    ["x-http-method-override"]=true,
    ["x-att-deviceid"]=true,
    ["x-wap-profile"]=true,
    ["proxy-connection"]=true,
    ["x-uidh"]=true,
    ["x-csrf-token"]=true,
    ["x-request-id"]=true,
    ["x-correlation-id"]=true,
    ["save-data"]=true,
}

local _M = {}

_M._VERSION = 0.1

local function send_api_discovery_request(premature, request_info, token, version, nameservers)
   if premature then
       return
   end

   
   local r, err = resolver:new{
       nameservers = nameservers,
       retrans = 5,
       timeout = 2000,
       no_random = true,
   }  

   local answers, err, tries = r:query(discovery_host, nil, {})
   if not answers then
      ngx.log(ngx.ERR,"Error while resolving DNS for " .. cjson.encode(discovery_host) .. " : " .. err)
      return
   end


   if answers.errcode then
      ngx.log(ngx.ERR,"Error while resolving DNS for " .. cjson.encode(discovery_host) .. " : " ..  answers.errcode..' - '..answers.errstr)
      return
   end
   local discovery_addresses = nil
   for i, ans in ipairs(answers) do
      if ans.type == 1 then 
         discovery_addresses = ans.address
         break
      end
   end 

   if not discovery_addresses then 
      ngx.log(ngx.ERR,"Error while resolving DNS for " .. cjson.encode(discovery_host) .. " : No ip address returned")
      return
   end
   
   local httpc = http.new()

   local ok,err = httpc:connect(discovery_addresses, 443)
   if not ok then
       err = err or ""
       ngx.log(ngx.ERR,"Error while connecting to api_inventory for " .. cjson.encode(discovery_addresses) .. " : " .. err)
       return
   end

   local ok, err = httpc:ssl_handshake(nil, discovery_host,false)
   if not ok then
       err = err or ""
       ngx.log(ngx.ERR,"Error while doing ssl handshake to api_inventory for " .. cjson.encode(discovery_addresses) .. " -> "..cjson.encode(discovery_host).." : " .. err)
       return
   end

   local res,err = httpc:request({
       path = "/discover/push",
       method = "POST",
       body = cjson.encode(request_info),
       headers = {
           ["Content-Type"] = "application/json",
           ["GoCache-Inventory-Token"] = token,
           ["GoCache-Inventory-Version"] = version,
       }
   })

   httpc:close()
   if not res then
       err = err or ""
       ngx.log(ngx.ERR,"Error while sending request to api_inventory for " .. cjson.encode(discovery_addresses) .. " -> "..cjson.encode(discovery_host) .. " : " .. err)
       return
   end   

   ngx.log(ngx.ERR, "Status code from sending "..(#request_info).." requests for discovery: "..res.status)                  
end

local function collect_cookie(collector, content)
   content = content .. ';'
   for segment in content:gmatch("(.-);") do 
      local name = segment:match("[%s%t]*(.-)=.+")
      if name then
         collector[name] = ""
      end
   end
end

local function obfuscate_cookies(params)
   local final_cookies = {}

   if type(params) == 'table' then 
      for __, data in pairs(params) do 
         collect_cookie(final_cookies,  data)
      end
   else 
      collect_cookie(final_cookies, params)
   end
 
   return final_cookies
end


local function obfuscate_headers(params)
   local final_headers = {}
   for key, content in pairs(params) do 
      if not ignore_headers[key] then
         final_headers[key] = ""
      end
   end
   return final_headers
end

local function obfuscate_parameters(params)

   local check_type = {}
            
   check_type["table"] = function()
      if params[1] ~= nil then
         local arrElement = params[1]
         params = nil
         params = {obfuscate_parameters(arrElement)}
      else
         for k, v in pairs(params) do
            params[k] = obfuscate_parameters(v)
         end
      end
      return params
   end
   check_type["string"] = function()
       return ""
   end
   check_type["boolean"] = function()
       return false
   end

   check_type["userdata"] = function()
       return nil
   end

   check_type["number"] = function()
       return 0
   end

   return check_type[type(params)]()
end


function _M.log()

   local request_time = ngx.now() - ngx.req.start_time()
   local response_headers = ngx.resp.get_headers()
   local res_content_type = response_headers["content_type"]

   local add = false
   if res_content_type ~= nil then
      for _, ct in ipairs(accepted_response_content_types) do
         if res_content_type:match(ct) then
            add = true 
            break
         end
      end
   end

   if add then
      local request_headers = ngx.req.get_headers()

      local req_content_type = request_headers.content_type

      local body_data
      for _, ct in ipairs(accepted_request_content_types) do
          if req_content_type:match(ct) then
              local raw_body_data = ngx.req.get_body_data()
              if raw_body_data ~= nil and #raw_body_data < inventory_max_body_size then

                  local success, jsonData = pcall(cjson.decode, raw_body_data) 
                  if success then
                      body_data = jsonData
                  else
                      body_data = ngx.req.get_post_args()
                  end
                  break
              end
          end
      end
      local body_info

      if body_data ~= nil then
          local obfuscated_body_data = obfuscate_parameters(body_data)
          body_info = cjson.encode(obfuscated_body_data)
      end

      local cookie_data
      local cookies = request_headers['cookie']
      if cookies then 
         cookie_data = obfuscate_cookies(cookies)
      end

      local uri = ngx.var.request_uri
      local queryIndex = string.find(uri,"?")
      local query
      if queryIndex ~= nil then
            query = string.sub(uri,queryIndex+1)
            uri = string.sub(uri,1,queryIndex-1)
      end
               
      local request_info = {
         hostname = ngx.var.http_host,
         uri = uri,
         query_string = query,
         status = ngx.status,
         method = ngx.var.request_method,
         res_content_type = res_content_type,
         req_content_type = req_content_type,
         body_data = body_info,
         header_data = obfuscate_headers(request_headers),
         cookie_data = cookie_data,
         request_time = request_time,
      }

      gcshared:lpush("requests", cjson.encode(request_info))

      local next_sent = gcshared:get("next_sent")
      next_sent = tonumber(next_sent) or 0

      if next_sent <= ngx.now() or gcshared:llen("requests") >= max_requests_store then 
         
         gcshared:set("next_sent", ngx.now()+requests_retention_seconds)
         local content = {}
         for i=1, max_requests_store do 
            local req_info = gcshared:rpop("requests")
            if req_info then 
               local req_data = cjson.decode(req_info)
               content[#content+1] = req_data
            end
         end
         if #content > 0 then 
            local nameservers = {}
            for ip in (resolver_nameservers..','):gmatch("(.-),") do 
               local ns = ip:match("%s*([0-9%.]+)%s*") 
               nameservers[#nameservers+1] = ns
            end
            ngx.timer.at(1, send_api_discovery_request, content, token, _M._VERSION, nameservers)
         end
      end
   end
end


return _M
