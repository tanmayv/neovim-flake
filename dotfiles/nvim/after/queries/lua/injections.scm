; extends
((comment) @injection.content
  (#match? @injection.content "^--\\[\\[")
  (#set! injection.language "markdown")
  ; Only strip the first 4 chars (--[[). Leave the end (0 0) untouched to prevent errors.
  ; (#offset! @injection.content 0 4 0 0)
  )
