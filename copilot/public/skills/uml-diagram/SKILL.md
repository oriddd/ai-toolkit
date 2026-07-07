---
name: uml-diagram
description: Create and maintain UML diagrams using Mermaid to visualize system architecture, component relationships, and interaction flows. Renders natively on GitHub/GitLab without external tools. Use when documenting system design, explaining complex flows, or updating architecture documentation.
tier: should
applies_to: [rest, event, scheduler, library, monolith]
depends_on: []
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-06-28
---

# UML Diagram Skill (Mermaid)

Create and maintain Mermaid diagrams to visualize system architecture, components, and interactions. Mermaid diagrams render natively on GitHub, GitLab, and many modern documentation platforms - no external tools needed!

## Why Mermaid?

### Advantages ✅
- **Native Rendering**: GitHub, GitLab, Azure DevOps all render Mermaid directly
- **No Build Step**: No need to generate images - diagrams render from markdown
- **Easy Editing**: Edit directly on GitHub web interface
- **Version Control**: Just markdown text, perfect for git
- **Live Preview**: Most IDEs support Mermaid preview
- **Simpler**: Easier syntax than PlantUML
- **Modern**: Active development, growing ecosystem

### vs PlantUML
PlantUML is more feature-rich but requires:
- Java installation
- External tool to generate images
- Committing generated images to git
- Regenerating on every change

**Verdict**: Mermaid is better for modern GitHub-based projects.

## When to Use

Apply this skill when:
- ✅ Documenting new system architecture
- ✅ Explaining component relationships
- ✅ Visualizing sequence flows
- ✅ Creating technical documentation
- ✅ Onboarding new team members
- ✅ Reviewing system design
- ✅ Planning architecture changes

## Diagram Types

## Diagram Types

### 1. System Context / Architecture Diagrams

#### System Context Diagram
**Purpose**: Show the system in its environment with external dependencies

**Template**:
````markdown
```mermaid
graph TB
    User[("👤 User<br/>Description")]
    App["📦 Main System<br/><i>What it does</i>"]
   External[("🔒 External System<br/><i>What it does</i>")]
    
    User -->|"Uses<br/>Protocol"| App
    App -->|"Integrates with<br/>Protocol"| External
    
    style App fill:#1168bd,stroke:#0b4884,color:#ffffff
    style External fill:#999999,stroke:#666666,color:#ffffff
```
````

**When to Create**: At project start, or when external dependencies change

**Example**: See [`context/system-context.md`](../../../context/system-context.md)

#### Component/Container Diagram
**Purpose**: Show high-level technology choices and component interactions

**Template**:
````markdown
```mermaid
graph TB
    subgraph system["📦 System Name"]
        web["🌐 Web Application<br/><i>Spring Boot</i>"]
        db[("💾 Database<br/><i>PostgreSQL</i>")]
        worker["⚙️ Background Worker<br/><i>Java</i>"]
    end
    
    User -->|"Uses<br/>HTTPS"| web
    web -->|"Reads/Writes<br/>JDBC"| db
    web -->|"Enqueues jobs<br/>RabbitMQ"| worker
    
    style system fill:#e1f5ff,stroke:#1168bd
```
````

**Example**: See [`context/component-diagram.md`](../../../context/component-diagram.md)

### 2. Sequence Diagrams

**Purpose**: Show interactions over time between components

**Template**:
````markdown
```mermaid
sequenceDiagram
    actor User
    participant Controller
    participant Service
    participant Repository
    participant Database
    
    User->>+Controller: POST /api/endpoint
    Controller->>+Service: processRequest(data)
    Service->>+Repository: save(entity)
    Repository->>+Database: INSERT
    Database-->>-Repository: success
    Repository-->>-Service: savedEntity
    Service-->>-Controller: result
    Controller-->>-User: 200 OK
```
````

**Common Patterns**:

**Error Handling**:
````markdown
```mermaid
sequenceDiagram
    Service->>Repository: process()
    
    alt Success Path
        Repository-->>Service: result
        Service-->>Controller: success
    else Error Path
        Repository-->>Service: Exception
        Service-->>Controller: Error
        Controller-->>User: 500 Error
    end
```
````

**Async Processing**:
````markdown
```mermaid
sequenceDiagram
    Service->>+Queue: enqueue(job)
    Queue-->>-Service: accepted
    
    Note over Service,Queue: Later...
    
    Worker->>+Queue: dequeue()
    Queue-->>-Worker: job
    Worker->>Worker: process()
```
````

**Loops**:
````markdown
```mermaid
sequenceDiagram
    Service->>Repository: getItems()
    
    loop For each item
        Repository->>Service: item
        Service->>Service: process(item)
    end
```
````

**Example**: See [`context/domain-flow.md`](../../../context/domain-flow.md)

### 3. Class Diagrams

**Purpose**: Show class structure and relationships

**Template**:
````markdown
```mermaid
classDiagram
    class ProcessRequest {
        -String requestId
        -String type
        -byte[] payload
        +validate() boolean
    }

    class ProcessingStrategy {
        <<interface>>
        +supports(request) boolean
        +process(request) Result
    }

    class CsvProcessor {
        +supports(request) boolean
        +process(request) Result
    }

    class ProcessorRegistry {
        -List~ProcessingStrategy~ strategies
        +getProcessor(type) ProcessingStrategy
    }

    ProcessingStrategy <|.. CsvProcessor : implements
    ProcessorRegistry --> ProcessingStrategy : uses
    ProcessRequest ..> ProcessingStrategy : uses
```
````

**Relationship Types**:
- `<|--` : Inheritance
- `*--` : Composition
- `o--` : Aggregation
- `-->` : Association
- `..|>` : Realization/Implementation
- `..>` : Dependency

### 4. State Diagrams

**Purpose**: Show state transitions

**Template**:
````markdown
```mermaid
stateDiagram-v2
    [*] --> Pending : submit
    
    Pending --> Processing : start
    Processing --> Completed : success
    Processing --> Failed : error
    
    Failed --> Pending : retry
    Failed --> [*] : abandon
    
    Completed --> [*]
```
````

### 5. Entity Relationship Diagrams (ERD)

**Purpose**: Database schema visualization

**Template**:
````markdown
```mermaid
erDiagram
    USER ||--o{ CONVERSION : creates
    USER {
        bigint id PK
        string email
        string name
        timestamp created_at
    }
    CONVERSION {
        bigint id PK
        bigint user_id FK
        string source_format
        string target_format
        string status
        timestamp created_at
    }
```
````

### 6. Flowcharts

**Purpose**: Process flows and decision trees

**Template**:
````markdown
```mermaid
flowchart TD
    Start([Start]) --> Input[/Get Input/]
    Input --> Validate{Valid?}
    
    Validate -->|Yes| Process[Process Data]
    Validate -->|No| Error[Show Error]
    
    Process --> Save[(Save to DB)]
    Save --> End([End])
    Error --> End
```
````

### 7. Gantt Charts

**Purpose**: Project timelines and schedules

**Template**:
````markdown
```mermaid
gantt
    title Project Timeline
    dateFormat YYYY-MM-DD
    
    section Phase 1
    Foundation           :2026-06-01, 14d
    Core Functionality   :2026-06-15, 21d
    
    section Phase 2
    Testing & Quality    :2026-07-06, 14d
    Observability        :2026-07-20, 7d
```
````

## Mermaid Setup

### No Installation Required! 🎉

Mermaid renders automatically on:
- ✅ **GitHub** - Native support in markdown files
- ✅ **GitLab** - Native support in markdown files
- ✅ **Azure DevOps** - Native support
- ✅ **Notion** - Supports Mermaid blocks
- ✅ **Confluence** - Via Mermaid plugin
- ✅ **VS Code** - Via extensions
- ✅ **IntelliJ IDEA** - Via plugins

### IDE Integration

**VS Code**:
1. Install "Markdown Preview Mermaid Support" extension
2. Or install "Mermaid Editor" for dedicated view
3. Open any `.md` file with Mermaid diagram
4. Press `Ctrl+Shift+V` (Cmd+Shift+V on Mac) to preview

**IntelliJ IDEA**:
1. Install "Mermaid" plugin from marketplace
2. Open `.md` file → preview shows automatically
3. Or use built-in markdown preview (supports Mermaid natively in newer versions)

**Eclipse**:
1. Install "Markdown Editor" with Mermaid support
2. Open `.md` file → preview renders Mermaid

### Online Editors

- **Mermaid Live Editor**: https://mermaid.live/
- **Draw.io**: Supports Mermaid import
- **GitHub**: Edit directly in web interface and preview

### CLI Tool (Optional)

If you need to generate static images:

```bash
# Install globally
npm install -g @mermaid-js/mermaid-cli

# Generate PNG
mmdc -i diagram.md -o diagram.png

# Generate SVG
mmdc -i diagram.md -o diagram.svg

# Generate PDF
mmdc -i diagram.md -o diagram.pdf
```

But usually **not needed** - just commit the `.md` files!

## Best Practices

### 1. Keep Diagrams Simple
- One concept per diagram
- Max 7-10 components per diagram
- Split complex systems into multiple diagrams

### 2. Use Consistent Naming
- Match code class/component names
- Use descriptive names
- Follow naming conventions from code

### 3. Layer Your Diagrams
- **Level 1**: System Context (external view)
- **Level 2**: Container (high-level tech)
- **Level 3**: Component (detailed structure)
- **Level 4**: Code (class diagrams)

### 4. Keep Updated
- Update diagrams when code changes
- Review diagrams during code reviews
- Include diagram updates in PR checklist

### 5. Version Control
- Store `.md` files in git (native rendering)
- No need to commit generated images (reduces repo size/noise)
- Keep diagrams close to code they document

## Common Patterns

### Strategy Pattern Visualization

````markdown
```mermaid
classDiagram
    class Strategy {
        <<interface>>
        +execute()
    }
    class ConcreteStrategyA
    class ConcreteStrategyB
    class Context {
        -Strategy strategy
        +executeStrategy()
    }
    Strategy <|.. ConcreteStrategyA
    Strategy <|.. ConcreteStrategyB
    Context --> Strategy
```
````

### Event-Driven Architecture

````markdown
```mermaid
sequenceDiagram
    participant Producer
    participant Bus as Event Bus
    participant ConsumerA
    participant ConsumerB

    Producer->>Bus: publish(event)
    Bus->>ConsumerA: event
    Bus->>ConsumerB: event
```
````

### Repository Pattern

````markdown
```mermaid
classDiagram
    class Service {
        -Repository repository
    }
    class Repository {
        <<interface>>
        +findById(id) Entity
    }
    class JpaRepository
    class Entity
    
    Repository <|.. JpaRepository
    Service --> Repository
    Repository --> Entity
```
````

## Styling and Theming

Mermaid supports styling individual nodes and overall themes.

### Themes
You can set themes at the top of the mermaid block:
````markdown
```mermaid
%%{init: {'theme': 'dark'}}%%
graph TD
    A --> B
```
````
Available themes: `default`, `forest`, `dark`, `neutral`, `base`.

### Custom Node Styling
````markdown
```mermaid
graph TD
    A[Start] --> B{Process}
    B -->|Success| C[End]
    
    style A fill:#f9f,stroke:#333,stroke-width:4px
    style B fill:#bbf,stroke:#f66,stroke-width:2px,color:#fff,stroke-dasharray: 5 5
```
````

## Documentation Integration

### In README.md

````markdown
## Architecture

See our architecture diagrams:

- [System Context](context/system-context.md)
- [Component Diagram](context/component-diagram.md)

Diagrams are rendered natively in the browser on GitHub.
````

### In ADRs

````markdown
# ADR-001: Use Event-Driven Architecture

## Decision
We will use event-driven architecture.

## Interaction Flow
```mermaid
sequenceDiagram
    Producer->>Bus: event
    Bus->>Consumer: event
```
````

### In Context Documentation

Simply wrap the Mermaid code in a fenced code block with the `mermaid` language identifier.

## Validation

### Syntax Check

The best way to validate is:
1. **IDE Preview**: Most markdown plugins show errors if syntax is invalid.
2. **Mermaid Live Editor**: Paste your code into https://mermaid.live/ to verify.
3. **CLI**: Use `mmdc` to verify it compiles to image if needed.

### CI/CD Integration

You can use the Mermaid CLI in your pipeline to validate syntax:

**GitHub Actions**:
```yaml
- name: Validate Mermaid Syntax
  run: |
    npm install -g @mermaid-js/mermaid-cli
    for f in context/*.md; do
      mmdc -i "$f" -o /dev/null || exit 1
    done
```

## Troubleshooting

### Common Issues

**Issue**: Diagram doesn't render on GitHub
**Solution**: Ensure you used the ` ```mermaid ` identifier and closed it with ` ``` `. Also ensure it's in a `.md` file.

**Issue**: "Max levels exceeded"
**Solution**: Your diagram is too complex. Try splitting it into smaller sub-graphs or separate diagrams.

**Issue**: Sequence diagram arrows looking weird
**Solution**: Check the arrow syntax (`->>` for solid, `-->>` for dashed). Avoid mixing them if not intended.

## Examples

### Example 1: Main Domain Flow
See: [`context/domain-flow.md`](../../../context/domain-flow.md)

### Example 2: System Context
See: [`context/system-context.md`](../../../context/system-context.md)

### Example 3: Component Structure
See: [`context/component-diagram.md`](../../../context/component-diagram.md)

## Resources

- **Mermaid Official**: https://mermaid.js.org/
- **Mermaid Live Editor**: https://mermaid.live/
- **C4 with Mermaid**: https://mermaid.js.org/syntax/c4c.html
- **Mermaid Cheat Sheet**: https://mermaid.js.org/syntax/flowchart.html

## Related Skills

- [context-maintenance](../context-maintenance/SKILL.md) - Maintain context docs
- [documentation-and-adr](../documentation-and-adr/SKILL.md) - General documentation
- [architecture](../api-design/SKILL.md) - API design documentation

