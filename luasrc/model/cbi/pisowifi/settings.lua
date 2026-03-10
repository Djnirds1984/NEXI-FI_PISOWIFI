m = Map("pisowifi", "PisoWifi Settings", "Configure your PisoWifi hotspot settings here.")

s = m:section(TypedSection, "general", "General Settings")
s.anonymous = true

o = s:option(Flag, "enabled", "Enable PisoWifi", "Enable or disable the captive portal service.")
o.default = o.enabled

o = s:option(Value, "rate", "Rate per Minute (PHP)", "Set the rate for internet access.")
o.datatype = "ufloat"
o.default = "1.0"

o = s:option(Value, "welcome_msg", "Welcome Message", "Message displayed on the landing page.")
o.default = "Welcome to NEXI-FI PISOWIFI"

return m
