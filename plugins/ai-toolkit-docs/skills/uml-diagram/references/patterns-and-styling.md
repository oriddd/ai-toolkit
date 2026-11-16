# UML Diagram — patterns, styling and documentation integration

Loaded from [`uml-diagram`](../SKILL.md).

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
    class SqlRepository
    class Entity
    
    Repository <|.. SqlRepository
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
# ADR-0001 — Use Event-Driven Architecture

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
