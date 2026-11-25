function Link(link)
  local target = link.target
  if target:match("^[%a][%w+.-]*:") or target:match("^//") then
    return link
  end

  local path, suffix = target:match("^([^?#]*)(.*)$")
  if path:match("%.md$") then
    link.target = path:gsub("%.md$", ".html") .. suffix
  end
  return link
end
