"github.copilot.chat.customInstructionsInSystemMessage": true

### **CRITICAL** applyPatchInstructions Important

You MUST follow this block for all apply_patch tool instructions:

<applyPatchInstructionsImportant>
*** Update File: [file_path]
 [context_before] -> See below for further instructions on context.
-[old_code] -> Precede each line in the old code with a minus sign.
+[new_code] -> Precede each line in the new, replacement code with a plus sign.
 [context_after] -> See below for further instructions on context.

Prefix each line of old code with exactly one minus (-) before its original first character; keep the original indentation after it.
Prefix each line of new code with exactly one plus (+), the remainder of the line after the plus is the full new line content.
Prefix each line of context before and context after with exactly one space ( ) before its original first character; keep the original indentation after it.

WARNING: apply_patch calls will update the current content of the file.
- Any subsequent overlapping apply_patch calls require read_file tool call, otherwise the tool will fail.
- Use read_file to understand the current content from the file including 20-50 lines before and after the string you want to replace, otherwise you will miss content and the tool will fail.
- If you use grep_search to find where to edit, then you must use read_file to get the actual current content.
- [context_before], [context_after], and [old_code] MUST always have the exact current content from the file character-for-character (including indentation, whitespace, existing escaping, exact same unicode characters).

See below for an example of the patch format. If you propose changes to multiple regions in the same file, you should repeat the *** Update File header for each snippet of code to change:
<applyPatchCorrectExample>
*** Begin Patch
*** Update File: /Users/someone/pygorithm/searching/binary_search.py
@@ class BaseClass
@@   def method():
 [3 lines of pre-context]
-[old_code]
+[new_code]
+[new_code]
 [3 lines of post-context]
*** End Patch
</applyPatchCorrectExample>
</applyPatchInstructionsImportant>

- You MUST NEVER add visually similar Unicode characters to files EVER
  - Always use the plain double quote " (U+0022), never U+201C or U+201D
  - Always use the plain apostrophe ' (U+0027), never U+2018 or U+2019
  - Always use the plain space (U+0020); never use non-breaking, zero-width, or other Unicode space characters
  - Always use the hyphen-minus - (U+002D); never use en or em dashes (U+2013/U+2014)
  - Always use three periods ... for an ellipsis; never U+2026