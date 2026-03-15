# Fixed centralized key activation section
        elif [ "$ACTION" = "activate_centralized_license" ]; then
             SUPA_URL=$("$UCI" get pisowifi.license.supabase_url 2>/dev/null)
             SUPA_KEY=$("$UCI" get pisowifi.license.supabase_key 2>/dev/null)
             
             # DEBUG LOGGING
             echo "<!-- DEBUG: SUPA_URL=$SUPA_URL -->" >&2
             echo "<!-- DEBUG: SUPA_KEY length=${#SUPA_KEY} -->" >&2
             
             HW_MAC=$($CAT /sys/class/net/br-lan/address 2>/dev/null || $CAT /sys/class/net/eth0/address 2>/dev/null || echo "")
             HW_MAC=$(printf "%s" "$HW_MAC" | $TR -d ':' | $TR 'a-z' 'A-Z')
             HW_HEX="$HW_MAC"
             if command -v md5sum >/dev/null 2>&1 && [ -n "$HW_MAC" ]; then
                 HW_HEX=$(echo -n "$HW_MAC" | md5sum 2>/dev/null | awk '{print toupper(substr($1,1,16))}')
             fi
             HARDWARE_ID="CPU-$HW_HEX"
             
             C_KEY=$(get_post_var "centralized_key")
             
             # DEBUG LOGGING
             echo "<!-- DEBUG: Received C_KEY=$C_KEY -->" >&2
             echo "<!-- DEBUG: HARDWARE_ID=$HARDWARE_ID -->" >&2
             
             if [ -n "$C_KEY" ]; then
                 # DEBUG: Test the regex pattern
                 echo "<!-- DEBUG: Testing regex pattern -->" >&2
                 if echo "$C_KEY" | $GREP -Eqi "^CENTRAL-[a-fA-F0-9]+-[a-fA-F0-9]+$"; then
                     echo "<!-- DEBUG: Regex MATCHED -->" >&2
                     
                     # DEBUG: Log the database query
                     echo "<!-- DEBUG: Querying database with key: $C_KEY -->" >&2
                     echo "<!-- DEBUG: SUPA_URL=$SUPA_URL -->" >&2
                     echo "<!-- DEBUG: SUPA_KEY exists: $([ -n "$SUPA_KEY" ] && echo "YES" || echo "NO") -->" >&2
                     
                     supa_request "$SUPA_URL" "$SUPA_KEY" "centralized_keys?select=id,vendor_id,is_active&key_value=ilike.$C_KEY&limit=1"
                     
                     # DEBUG: Log the response
                     echo "<!-- DEBUG: HTTP_CODE=$SUPA_HTTP_CODE -->" >&2
                     echo "<!-- DEBUG: RESPONSE_BODY=$SUPA_BODY -->" >&2
                     
                     if [ "$SUPA_HTTP_CODE" = "200" ] && echo "$SUPA_BODY" | $GREP -q '"id"'; then
                         C_VENDOR=$(echo "$SUPA_BODY" | json_first "vendor_id")
                         C_ACTIVE=$(echo "$SUPA_BODY" | json_first "is_active")
                         
                         if [ "$C_ACTIVE" = "true" ]; then
                             "$UCI" set pisowifi.license.centralized_key="$C_KEY"
                             "$UCI" set pisowifi.license.centralized_vendor_id="$C_VENDOR"
                             "$UCI" set pisowifi.license.centralized_status="active"
                             "$UCI" commit pisowifi
                             
                             echo "Status: 302 Found"
                             echo "Location: /cgi-bin/admin?tab=settings&msg=centralized_ok"
                             echo ""
                             exit 0
                         else
                             # DEBUG: Log why it failed
                             echo "<!-- DEBUG: Key found but not active or invalid response -->" >&2
                             echo "<!-- DEBUG: C_ACTIVE=$C_ACTIVE -->" >&2
                             echo "Status: 302 Found"
                             echo "Location: /cgi-bin/admin?tab=settings&msg=centralized_failed"
                             echo ""
                             exit 0
                         fi
                     else
                         # DEBUG: Log database query failure
                         echo "<!-- DEBUG: Primary database query failed -->" >&2
                         echo "<!-- DEBUG: HTTP_CODE=$SUPA_HTTP_CODE -->" >&2
                         echo "<!-- DEBUG: Checking fallback table... -->" >&2
                         
                         # Fallback: check pisowifi_openwrt table just in case they used that for centralized keys
                        supa_request "$SUPA_URL" "$SUPA_KEY" "pisowifi_openwrt?select=id,status,vendor_uuid&license_key=ilike.$C_KEY&limit=1"
                        
                        # DEBUG: Log fallback response
                        echo "<!-- DEBUG: Fallback HTTP_CODE=$SUPA_HTTP_CODE -->" >&2
                        echo "<!-- DEBUG: Fallback RESPONSE_BODY=$SUPA_BODY -->" >&2
                        
                         if [ "$SUPA_HTTP_CODE" = "200" ] && echo "$SUPA_BODY" | $GREP -q '"id"'; then
                             C_VENDOR=$(echo "$SUPA_BODY" | json_first "vendor_uuid")
                             C_STATUS=$(echo "$SUPA_BODY" | json_first "status")
                             
                             if [ "$C_STATUS" = "active" ]; then
                                 "$UCI" set pisowifi.license.centralized_key="$C_KEY"
                                 "$UCI" set pisowifi.license.centralized_vendor_id="$C_VENDOR"
                                 "$UCI" set pisowifi.license.centralized_status="active"
                                 "$UCI" commit pisowifi
                                 
                                 echo "Status: 302 Found"
                                 echo "Location: /cgi-bin/admin?tab=settings&msg=centralized_ok"
                                 echo ""
                                 exit 0
                             fi
                         fi
                         
                         # DEBUG: Log final failure
                         echo "<!-- DEBUG: Both database queries failed -->" >&2
                         echo "<!-- DEBUG: Final failure - key not found or connection error -->" >&2
                         
                         echo "Status: 302 Found"
                         echo "Location: /cgi-bin/admin?tab=settings&msg=centralized_failed"
                         echo ""
                         exit 0
                     fi
                 else
                     echo "<!-- DEBUG: Regex FAILED for key: $C_KEY -->" >&2
                     echo "<!-- DEBUG: Expected format: CENTRAL-XXXXXXXX-XXXXXXXX -->" >&2
                     echo "Status: 302 Found"
                     echo "Location: /cgi-bin/admin?tab=settings&msg=centralized_format_error"
                     echo ""
                     exit 0
                 fi
             else
                 echo "Status: 302 Found"
                 echo "Location: /cgi-bin/admin?tab=settings&msg=centralized_invalid_format"
                 echo ""
                 exit 0
             fi