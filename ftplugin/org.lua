local ok, bullets = pcall(require, "org-bullets")
if not ok then
  return vim.notify(
    "Org bullets is not available, please ensure it is loaded",
    vim.log.levels.ERROR
  )
end
bullets.__init()
