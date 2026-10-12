# Validates payload/contexts.txt: "path context [mode]" per line. Used by host and container.
function err(m) { printf "error: contexts.txt line %d: %s\n", NR, m > "/dev/stderr"; bad = 1 }
{ sub(/\r$/, "") }
/^[ \t]*(#|$)/ { next }
{
  if (NF < 2 || NF > 3) { err("expected: path context [mode]"); next }
  if (substr($1, 1, 1) != "/") err("path must be absolute: " $1)
  if ($2 !~ /^u:object_r:[a-z0-9_]+:s0$/) err("bad label '" $2 "' (want u:object_r:<type>:s0)")
  if (NF == 3 && $3 !~ /^0?[0-7][0-7][0-7]$/) err("bad mode '" $3 "' (want 3 octal digits with optional leading 0; setuid/setgid/sticky are not supported)")
}
END { exit bad }
