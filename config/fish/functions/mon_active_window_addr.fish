function mon_active_window_addr --argument-names mon_name
    set -l m (hyprctl monitors -j)
    set -l mid (echo $m | jq -r --arg n "$mon_name" '.[] | select(.name==$n) | .id')
    test -n "$mid"; or return 2
    set -l ws (echo $m | jq -r --argjson id $mid '.[] | select(.id==$id) | .activeWorkspace.id')
    hyprctl clients -j | jq -r --argjson mid $mid --argjson ws $ws \
        'map(select(.monitor==$mid and .workspace.id==$ws)) | sort_by(.focusHistoryID) | last | .address // empty'
end
