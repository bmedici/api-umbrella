local api_key_validator = require "api_key_validator"
local api_matcher = require "api_matcher"
local api_settings = require "api_settings"
local error_handler = require "error_handler"
local ip_validator = require "ip_validator"
local rate_limit = require "rate_limit"
local referer_validator = require "referer_validator"
local rewrite_request = require "rewrite_request"
local role_validator = require "role_validator"
local user_settings = require "user_settings"

local ngx_var = ngx.var

-- Cache various "ngx.var" lookups that are repeated throughout the stack,
-- so they don't allocate duplicate memory during the request, and since
-- ngx.var lookups are apparently somewhat expensive.
ngx.ctx.arg_api_key = ngx_var.arg_api_key
ngx.ctx.host = ngx_var.http_x_forwarded_host or ngx_var.http_host or ngx_var.host
ngx.ctx.http_x_api_key = ngx_var.http_x_api_key
ngx.ctx.port = ngx_var.http_x_forwarded_port or ngx_var.server_port
ngx.ctx.protocol = ngx_var.http_x_forwarded_proto or ngx_var.scheme
ngx.ctx.remote_addr = ngx_var.remote_addr
ngx.ctx.remote_user = ngx_var.remote_user
ngx.ctx.request_method = string.lower(ngx.var.request_method)
ngx.ctx.uri = ngx_var.uri

-- When nginx is first starting or the workers are being reloaded (SIGHUP),
-- pause the request serving until the API config and upstreams have been
-- configured. This prevents temporary 404s (api config not yet fetched) or bad
-- gateway errors (upstreams not yet configured) during startup or reloads.
--
-- TODO: balancer_by_lua is supposedly coming soon, which I think might offer a
-- much cleaner way to deal with all this versus what we're currently doing
-- with dyups. Revisit if that gets released.
-- https://groups.google.com/d/msg/openresty-en/NS2dWt-xHsY/PYzi5fiiW8AJ
local upstreams_inited = ngx.shared.apis:get("upstreams_inited")
if not upstreams_inited then
  local wait_time = 0
  local sleep_time = 0.1
  local max_time = 15
  repeat
    ngx.sleep(sleep_time)
    wait_time = wait_time + sleep_time
    upstreams_inited = ngx.shared.apis:get("upstreams_inited")
  until upstreams_inited or wait_time > max_time

  -- This really shouldn't happen, but if things don't appear to be
  -- initializing properly within a reasonable amount of time, log the error
  -- and try continuing anyway.
  if not upstreams_inited then
    ngx.log(ngx.ERR, "Failed to initialize config or upstreams within expected time. Trying to continue anyway...")
  end
end

-- Try to find the matching API backend first, since it dictates further
-- settings and requirements.
local api, url_match, err = api_matcher()
if err then
  return error_handler(err)
end

-- Fetch the settings from the matched API.
local settings, err = api_settings(api)
if err then
  return error_handler(err, settings)
end

-- Validate the API key that's passed in, if this API requires API keys.
local user, err = api_key_validator(settings)
if err then
  return error_handler(err, settings)
end

-- Fetch and merge any user-specific settings.
local err = user_settings(settings, user)
if err then
  return error_handler(err, settings)
end

-- If this API requires roles, verify that the user has those.
local err = role_validator(settings, user)
if err then
  return error_handler(err, settings)
end

-- If this API or user requires the traffic come from certain IP addresses,
-- verify those.
local err = ip_validator(settings, user)
if err then
  return error_handler(err, settings)
end

-- If this API or user requires the traffic come from certain HTTP referers,
-- verify those.
local err = referer_validator(settings, user)
if err then
  return error_handler(err, settings)
end

-- If we've gotten this far, it means the user is authorized to access this
-- API, so apply the rate limits for this user and API.
local err = rate_limit(settings, user)
if err then
  return error_handler(err, settings)
end

-- Perform any request rewriting.
local err = rewrite_request(user, api, settings)
if err then
  return error_handler(err, settings)
end
