# UML Diagram — more diagram types

Loaded from [`uml-diagram`](../SKILL.md); section numbers match the originals.

## 2b. Sequence patterns: async processing and loops

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

## 3. Class Diagrams

**Purpose**: Show class structure and relationships

**Template**:
````markdown
```mermaid
classDiagram
    class ProcessRequest {
        -String requestId
        -String type
        -bytes payload
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
        -ProcessingStrategy[] strategies
        +getProcessor(type) ProcessingStrategy
    }

    ProcessingStrategy <|.. CsvProcessor : implements
    ProcessorRegistry --> ProcessingStrategy : uses
    ProcessRequest ..> ProcessingStrategy : uses
```
````

Type names follow the project's language: `String` / `str` / `string`, and a collection as `List~T~` (Java), `list~T~` (Python) or `T[]` (TypeScript).

**Relationship Types**:
- `<|--` : Inheritance
- `*--` : Composition
- `o--` : Aggregation
- `-->` : Association
- `..|>` : Realization/Implementation
- `..>` : Dependency

## 4. State Diagrams

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

## 5. Entity Relationship Diagrams (ERD)

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

## 6. Flowcharts

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

## 7. Gantt Charts

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
