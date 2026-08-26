---
scope:
  - '**/*.cs'
title: C# Standards
---
# C# Standards

Applies to all C# we write. Code that models or orchestrates the domain is the strict zone; a wrapper
around a foreign object model relaxes only at its internal surface.

## Error handling

- `Result<TValue, Error>` for anything that can fail. Never exceptions for expected outcomes.
- `Maybe<T>` for optional values. Prefer it to nullable `T?` in return positions.
- `Result<Maybe<T>, Error>` when an operation can fail *and* legitimately find nothing.
- Only `CSharpFunctionalExtensions` — no `OneOf`, `ErrorOr`, `FluentResults`, or a home-grown
  `Result<T>`. Parallel libraries fragment the domain language and break combinator chains.
- Compose with combinators. An interior `if (r.IsFailure) return r.Error; var x = r.Value;`
  ladder is the anti-pattern `Bind`/`Map`/`Match` exist to remove.
- Exceptions are for programmer error (guard clauses), not business outcomes.

### Domain errors

Static factory per concept, living beside the slice that raises it. Promote to a shared
`Common/Errors/` only on a second consumer.

```csharp
public static class DocumentErrors
{
    public static readonly Error NotFound = new("Document.NotFound");
    public static Error InvalidPath(string path) => Error.For("Document.InvalidPath", path);
}
```

Codes are `Concept.Condition`, stable, and safe to switch on. What an `Error` carries beyond its code
— a message, arguments, both — is a per-repo contract; the factory shape above holds either way.

`DomainException` means a violated invariant — a bug — never a business case.

## Value objects

`sealed record`, get-only properties, private constructor, static `Create` returning `Result`.

```csharp
public sealed record Email
{
    public string Value { get; }
    private Email(string value) => Value = value;

    public static Result<Email, Error> Create(string input) =>
        string.IsNullOrWhiteSpace(input) || !input.Contains('@')
            ? DomainErrors.Email.Invalid(input)
            : new Email(input.Trim());
}
```

Never a positional record or `init` properties on a value object — a public primary constructor
bypasses `Create`, and `with { X = }` bypasses validation.

**Parse, don't validate.** Validate once at the edge and return the typed value. Downstream code
takes `Email`, not `string`, and re-validation disappears.

## State

Model lifecycle as a closed `abstract record` hierarchy — one type per state, each carrying only
its own data. Never `enum` plus nullable companion fields: it forces nullables, every read
re-checks the enum, and methods valid in one state exist on all of them.

A method that must throw "not allowed in this state" belongs on the state record where it *is*
valid. Illegal calls should be compile errors, not runtime ones.

Because C# has no exhaustiveness over class hierarchies, a sum's `switch` must carry a catch-all.
Its presence is never the defect; needing it to be *correct* is — that behaviour belonged on a leaf.

## Dependencies

Constructor injection only. No service locator, no `IConfiguration` read inside a handler.
A constructor parameter may be a named delegate rather than an interface when the collaborator
genuinely is a function — a rule, policy, selector, or clock.

Configuration through the options pattern, validated at startup.

## Naming

Names match the terms the business uses. If a domain practitioner would not recognise the concept
from the method name, the name is wrong.

| Element | Convention |
|---|---|
| Private field | `_camelCase` |
| Local / parameter | `camelCase` |
| Property / method | `PascalCase` |
| Async method | `PascalCase` + `Async` |
| Interface | `I` + `PascalCase` |
| Boolean | `Is`/`Has`/`Can`/`Should` prefix |
| Test method | `MethodName_Scenario_ExpectedResult` |

| Suffix | Role |
|---|---|
| `Handler`, `Command`/`Query`, `Validator` | Use case |
| `Dto` | Shared data shape |
| `Decorator` | Cross-cutting wrapper |
| `Repository` | Data store access |
| `Client`, `Adapter`, `Mapper`, `Provider`, `Factory` | External access / transformation |
| `Options` / `Settings` | Config POCO / typed accessor |
| `Wrapper`, `Finder`, `Detector` | Foreign-object-model abstraction / search / state read |
| `Controller`, `EventHandler` | UI or host event to command |

Where each suffix *lives* is a per-repo decision — a repo states it in its own `.standards/`, because
the answer is that repo's project layout and nothing shared can know it.

**No `Helper`, `Manager`, `Utility`, or `Service` classes** — name the actual responsibility
(`Sender`, `Checker`, `Policy`, `Calculator`). Use-case orchestration is a `Handler`; an
Application-layer `XxxService` is a second dispatch path that bypasses the decorator chain, so it
gets no logging, timing, or entitlements. A pure cross-entity *decision* class is legitimate —
named for what it decides, never `Service`. Legacy `IXxxService` implementations are renamed as
touched, not en masse.

- **Length scales with scope** — `i` is fine in a three-line block; a name surviving a whole method
  is a descriptive phrase (`operativeParagraphs`, not `op`).
- **Name the concept, don't narrate the algorithm.** A member name is a noun phrase or a simple
  predicate, never a clause. Tells: a pronoun pointing at something that is not the receiver
  (`This`, `That`, `It`), odd tense, filler articles. Test methods and Gherkin steps are exempt.
- **Domain vocabulary means terms of art, not invented metaphor.** Keep words a practitioner knows;
  drop coinages only this codebase teaches.
- No Hungarian, no noise words (`data`, `info`, `obj`, `temp`), collections plural, no numbered
  twins (`sourceDocument`/`destinationDocument`, never `doc1`/`doc2`).

## Immutability and idioms

Records with `init` for DTOs and commands; `with` to modify. `IReadOnlyList<T>` on public surfaces.
Sealed by default.

`is null` / `is not null` over `== null` · `StringComparison` on every string comparison ·
`DateTimeOffset` over `DateTime` · `nameof` over string literals.

## Anti-patterns

| Anti-pattern | Use instead |
|---|---|
| MediatR | Direct handler injection |
| Mutable DTOs | Records with `init` |
| Exceptions for control flow | `Result<T, Error>` |
| Service locator | Constructor injection |
| `dynamic`, `#region`, `async void`, commented-out code | Delete or restructure |
| `BinaryFormatter` | `System.Text.Json` |
| `enum` + nullable companions for lifecycle | Closed record hierarchy |
| `public DateTime CreatedAt { get; set; }` on an entity | Value object enforcing UTC, `init` not `set` |
| `if (person.Age < 18)` interrogating another object's data | Named predicate on the owner: `person.IsMinor` |
| `bool hasX, bool hasY, bool hasZ` travelling together | Value object owning the flags, or a sum type |
| A parameter recoverable from another parameter | Derive it inside — two sources of truth can disagree |

## Comments

Reaching for a comment is evidence the code is wrong. Rename, extract, or give the concept an
owning type, and the comment stops being needed.

**Hard cap: one line.** A fact needing a paragraph is a missing abstraction, an ADR, or a test
name. One line is earned only for what code cannot express: a wire-format quirk, an external
constraint, a non-obvious *why*. Public-API XML docs get one concise line, and only where the
signature does not already say it.

Never: narrative `<summary>` blocks, comments addressed to the reviewer ("now correctly handles X"),
section banners or `// Step 1:` numbering, or restatements of the code.
