---
scope:
  - '**/WordAddIn/**/*.cs'
  - '**/PowerPointAddIn/**/*.cs'
title: VSTO & COM Interop
---
# VSTO & COM Interop

Applies to any VSTO add-in we write.

## COM object disposal

Office COM objects are not garbage collected reliably. Release every RCW you materialise,
in a `finally`, in reverse order of acquisition.

```csharp
Word.Sections sections = null;
Word.Section  section  = null;
Word.Range    range    = null;
try
{
    sections = document.Sections;
    section  = sections[1];
    range    = section.Range;
    range.Text = "Hello";
}
finally
{
    if (range    is not null) Marshal.ReleaseComObject(range);
    if (section  is not null) Marshal.ReleaseComObject(section);
    if (sections is not null) Marshal.ReleaseComObject(sections);
}
```

Two rules carry the weight:

- **Release in reverse order** — child before parent.
- **Never release something you did not materialise.** Do not release a `document` the caller
  owns, and do not declare-then-release a variable you never assigned: the null check makes it
  silent, not correct.

Use `= null` (not `null!`) — VSTO projects set `<Nullable>disable</Nullable>`. Use `is not null`
(not `!= null`).

### Indexed loop over a COM collection

```csharp
var paragraphs = document.Paragraphs;
try
{
    for (int i = 1; i <= paragraphs.Count; i++)
    {
        Word.Paragraph p = null;
        Word.Range     r = null;
        try
        {
            p = paragraphs[i];
            r = p.Range;
            r.Bold = 1;
        }
        finally
        {
            if (r is not null) Marshal.ReleaseComObject(r);
            if (p is not null) Marshal.ReleaseComObject(p);
        }
    }
}
finally
{
    Marshal.ReleaseComObject(paragraphs);
}
```

Never `foreach` or LINQ over a COM collection — the enumerator materialises RCWs you cannot release.

### `GC.Collect` after a batch

The double-collect pattern forces RCW finalisation. It is a last resort for known shutdown
boundaries; reaching for it routinely means the disposal flow is wrong.

## Lifecycle

`ThisAddIn` does DI bootstrap and event wiring **only** — no COM access and no business logic in
`ThisAddIn_Startup`. Documents are not necessarily open at startup.

```csharp
private void ThisAddIn_Startup(object sender, EventArgs e)
{
    Application.DocumentOpen += Application_DocumentOpen;
}

private void ThisAddIn_Shutdown(object sender, EventArgs e)
{
    // unwire handlers, release retained COM references
}
```

Never cache `ActiveDocument` in a field. Never store a COM reference in an event-handler field.

## Performance

Batch Office operations behind a `ScreenUpdating` toggle restored in `finally`.

```csharp
app.ScreenUpdating = false;
try { /* bulk work */ }
finally { app.ScreenUpdating = true; }
```

## Error handling

Translate `COMException` into `Result<T, Error>` at the interop boundary. Do not swallow it to a
log — a logged-and-discarded COM failure returns a success the caller cannot distinguish from a
real one.

```csharp
try
{
    // Office API calls
}
catch (COMException ex)
{
    return DocumentErrors.InsertFieldError(ex.Message);
}
```

Logging is a `TapError` concern, not a substitute for returning the failure.

## What lives in the AddIn project (hard rule)

**Only code requiring Office interop or WinForms/WPF belongs in AddIn projects.** Two reasons a
class belongs there:

1. **Office Object Model** — has `using Microsoft.Office.Interop.Word` (or PowerPoint)
2. **WinForms / WPF UI** — has `using System.Windows.Forms` or similar

**Test:** check the `using` statements. If neither applies, the class belongs in Application or
Infrastructure.

- AddIn adapts Office events and UI only — it must call Application commands/queries
- No business logic, validation, or orchestration in the AddIn: an `if` deciding a business
  outcome belongs in a handler
- DMS integrations, API clients, file system access, config loading → Infrastructure
- Domain and Application layers stay Office-agnostic
- Use the adapter pattern to translate between domain types and the Object Model
