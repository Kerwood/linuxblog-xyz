---
title: Removing the Proxmox Subscription Message
date: 2026-08-03 18:13:00
author: Patrick Kerwood
excerpt: A quick tutorial on how to remove the "No valid subscription" nag message from the Proxmox web UI, and make it stick across updates.
type: post
blog: true
tags: [proxmox]
meta:
  - name: description
    content: How to remove the "No valid subscription" nag message from the Proxmox web UI and keep it removed after updates.
---
{{ $frontmatter.excerpt }}

If you run Proxmox without a subscription, you get a "No valid subscription" popup every time you log in to the web UI. Here is how to get rid of it.

The message is rendered by a JavaScript file that ships with the `proxmox-widget-toolkit` package. We can patch it, but the patch gets overwritten whenever the package is updated. To make it permanent, we add an apt hook that re-applies the patch after every update.

Create the script that removes the subscription message.

```sh
cat > /usr/local/bin/pve-remove-nag.sh <<'EOF'
#!/bin/sh
JS=/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js

[ -f "$JS" ] || exit 0

echo 'Removing subscription nag from UI...'
sed -i "s/data\.status\.toLowerCase() !== 'active'/false/g" "$JS"
EOF
```

Make it executable.

```sh
chmod +x /usr/local/bin/pve-remove-nag.sh
```

Add an apt hook so the script runs automatically after every package operation, keeping the nag removed across updates.

```sh
echo 'DPkg::Post-Invoke { "/usr/local/bin/pve-remove-nag.sh || true"; };' \
  > /etc/apt/apt.conf.d/no-nag-script
```

Verify the apt hook is registered.

```sh
apt-config dump | grep -i post-invoke
```

Now reinstall the package to trigger the hook and apply the patch.

```sh
apt install --reinstall proxmox-widget-toolkit
```

Confirm the patch was applied. This should return `0`.

```sh
grep -c "toLowerCase() !== 'active'" \
  /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
```

Finally, do a hard refresh (`Ctrl + Shift + R`) in your browser to clear the cached JavaScript, and the message is gone.
