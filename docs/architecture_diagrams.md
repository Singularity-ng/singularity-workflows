# Pgflow Architecture Diagrams

This document contains comprehensive Mermaid diagrams showing the PGMQ + NOTIFY architecture and data flow.

## 🏗️ System Architecture

### High-Level Architecture

```mermaid
graph TB
    subgraph "Application Layer"
        A[Workflow Definition] --> B[Pgflow.Executor]
        C[AI/LLM System] --> D[Pgflow.FlowBuilder]
    end
    
    subgraph "Execution Engine"
        B --> E[Task Scheduler]
        D --> E
        E --> F[Dependency Resolver]
        F --> G[Parallel Executor]
    end
    
    subgraph "Database Layer"
        G --> H[PostgreSQL + pgmq]
        H --> I[workflows table]
        H --> J[tasks table]
        H --> K[pgmq queues]
    end
    
    subgraph "Notification Layer"
        H --> L[PostgreSQL NOTIFY]
        L --> M[Pgflow.Notifications]
        M --> N[Event Listeners]
        N --> O[Real-time Updates]
    end
    
    subgraph "External Systems"
        P[Observer Web UI] --> N
        Q[CentralCloud] --> N
        R[Genesis] --> N
    end
```

### PGMQ + NOTIFY Flow

```mermaid
sequenceDiagram
    participant W as Workflow
    participant E as Executor
    participant P as PostgreSQL
    participant Q as pgmq
    participant N as NOTIFY
    participant L as Listener
    
    W->>E: Execute workflow
    E->>P: Store workflow state
    E->>Q: Send task messages
    Q->>N: Trigger NOTIFY
    N->>L: Send notification
    L->>E: Process notification
    E->>P: Update task status
    E->>Q: Send completion message
    Q->>N: Trigger NOTIFY
    N->>L: Send completion notification
```

## 🔄 Workflow Execution Flow

### Static Workflow Execution

```mermaid
flowchart TD
    A[Define Workflow Module] --> B[Call Pgflow.Executor.execute]
    B --> C[Parse workflow steps]
    C --> D[Create dependency graph]
    D --> E[Store in PostgreSQL]
    E --> F[Send initial tasks to pgmq]
    F --> G[Trigger NOTIFY events]
    G --> H[Start parallel execution]
    H --> I{All dependencies met?}
    I -->|No| J[Wait for dependencies]
    I -->|Yes| K[Execute task]
    K --> L[Update task status]
    L --> M[Send completion to pgmq]
    M --> N[Trigger NOTIFY]
    N --> O{More tasks?}
    O -->|Yes| I
    O -->|No| P[Workflow Complete]
    J --> K
```

### Dynamic Workflow Creation

```mermaid
flowchart TD
    A[AI/LLM System] --> B[Call Pgflow.FlowBuilder.create_flow]
    B --> C[Create workflow record]
    C --> D[Add steps via add_step]
    D --> E[Define dependencies]
    E --> F[Store in PostgreSQL]
    F --> G[Generate step functions]
    G --> H[Call Pgflow.Executor.execute_dynamic]
    H --> I[Execute like static workflow]
```

## 🔔 Notification System

### NOTIFY Event Flow

```mermaid
sequenceDiagram
    participant T as Task
    participant E as Executor
    participant P as PostgreSQL
    participant Q as pgmq
    participant N as NOTIFY
    participant L as Listener
    participant O as Observer
    
    T->>E: Task completed
    E->>P: Update task status
    E->>Q: Send completion message
    Q->>N: Trigger pg_notify
    N->>L: Send notification
    L->>O: Update web UI
    O->>L: Acknowledge
```

### Notification Types and Flow

```mermaid
graph LR
    subgraph "Workflow Events"
        A[workflow_started] --> B[task_started]
        B --> C[task_completed]
        C --> D[workflow_completed]
    end
    
    subgraph "Error Events"
        E[task_failed] --> F[workflow_failed]
    end
    
    subgraph "Notification Channels"
        G[workflow_events] --> H[Observer Web UI]
        I[task_events] --> J[CentralCloud]
        K[approval_events] --> L[Genesis]
    end
    
    A --> G
    B --> I
    C --> I
    D --> G
    E --> I
    F --> G
```

## 📊 Data Flow Architecture

### Complete Data Flow

```mermaid
flowchart TB
    subgraph "Input Sources"
        A[Static Workflow] --> C[Executor]
        B[Dynamic Workflow] --> C
        D[AI Generated] --> E[FlowBuilder]
        E --> C
    end
    
    subgraph "Execution Engine"
        C --> F[Task Scheduler]
        F --> G[Dependency Resolver]
        G --> H[Parallel Executor]
    end
    
    subgraph "Storage Layer"
        H --> I[PostgreSQL]
        I --> J[workflows table]
        I --> K[tasks table]
        I --> L[task_dependencies table]
    end
    
    subgraph "Message Queue"
        H --> M[pgmq]
        M --> N[workflow_events queue]
        M --> O[task_events queue]
        M --> P[approval_events queue]
    end
    
    subgraph "Notification System"
        M --> Q[PostgreSQL NOTIFY]
        Q --> R[Pgflow.Notifications]
        R --> S[Event Listeners]
    end
    
    subgraph "External Systems"
        S --> T[Observer Web UI]
        S --> U[CentralCloud]
        S --> V[Genesis]
    end
    
    subgraph "Logging & Monitoring"
        R --> W[Structured Logging]
        W --> X[Debug Information]
        W --> Y[Performance Metrics]
    end
```

## 🧪 Testing Architecture

### Test Flow

```mermaid
flowchart TD
    A[Test Suite] --> B[Setup Test Database]
    B --> C[Create Test Workflows]
    C --> D[Execute Workflows]
    D --> E[Verify Results]
    E --> F[Test NOTIFY Events]
    F --> G[Test Error Handling]
    G --> H[Cleanup]
    H --> I[Generate Coverage Report]
```

### Integration Testing

```mermaid
sequenceDiagram
    participant T as Test Suite
    participant P as PostgreSQL
    participant Q as pgmq
    participant N as NOTIFY
    participant L as Test Listener
    
    T->>P: Setup test database
    T->>Q: Create test queues
    T->>L: Start test listener
    T->>P: Execute test workflow
    P->>Q: Send messages
    Q->>N: Trigger NOTIFY
    N->>L: Send test notification
    L->>T: Verify notification
    T->>P: Cleanup test data
```

## 🚀 Deployment Architecture

### Production Deployment

```mermaid
graph TB
    subgraph "Load Balancer"
        A[HAProxy/Nginx]
    end
    
    subgraph "Application Tier"
        B[Pgflow App 1]
        C[Pgflow App 2]
        D[Pgflow App 3]
    end
    
    subgraph "Database Tier"
        E[PostgreSQL Primary]
        F[PostgreSQL Replica]
        G[pgmq Extension]
    end
    
    subgraph "Monitoring"
        H[Prometheus]
        I[Grafana]
        J[ELK Stack]
    end
    
    A --> B
    A --> C
    A --> D
    B --> E
    C --> E
    D --> E
    E --> F
    E --> G
    B --> H
    C --> H
    D --> H
    H --> I
    H --> J
```

### Kubernetes Deployment

```mermaid
graph TB
    subgraph "Kubernetes Cluster"
        subgraph "Namespace: pgflow"
            A[Pgflow Deployment]
            B[PostgreSQL StatefulSet]
            C[pgmq Extension]
        end
        
        subgraph "Namespace: observer"
            D[Observer Deployment]
        end
        
        subgraph "Namespace: centralcloud"
            E[CentralCloud Deployment]
        end
    end
    
    subgraph "External Services"
        F[LoadBalancer Service]
        G[Ingress Controller]
    end
    
    F --> G
    G --> A
    G --> D
    G --> E
    A --> B
    B --> C
    D --> A
    E --> A
```

## 🔧 Configuration Flow

### Configuration Management

```mermaid
flowchart TD
    A[Environment Variables] --> B[Application Config]
    B --> C[Database Config]
    B --> D[pgmq Config]
    B --> E[Notification Config]
    
    C --> F[PostgreSQL Connection]
    D --> G[Queue Configuration]
    E --> H[NOTIFY Channels]
    
    F --> I[Database Operations]
    G --> J[Message Queue Operations]
    H --> K[Real-time Notifications]
```

## 📈 Performance Monitoring

### Monitoring Flow

```mermaid
graph TB
    subgraph "Application Metrics"
        A[Workflow Execution Time]
        B[Task Completion Rate]
        C[Error Rate]
        D[Queue Depth]
    end
    
    subgraph "Database Metrics"
        E[Query Performance]
        F[Connection Pool]
        G[Lock Contention]
    end
    
    subgraph "Notification Metrics"
        H[NOTIFY Latency]
        I[Event Processing Rate]
        J[Listener Health]
    end
    
    subgraph "Monitoring Stack"
        K[Prometheus]
        L[Grafana]
        M[AlertManager]
    end
    
    A --> K
    B --> K
    C --> K
    D --> K
    E --> K
    F --> K
    G --> K
    H --> K
    I --> K
    J --> K
    K --> L
    K --> M
```

## 🎯 Use Case Flows

### AI Workflow Generation

```mermaid
sequenceDiagram
    participant AI as AI System
    participant FB as FlowBuilder
    participant E as Executor
    participant P as PostgreSQL
    participant N as NOTIFY
    participant O as Observer
    
    AI->>FB: Generate workflow
    FB->>P: Create workflow
    FB->>P: Add steps
    FB->>E: Execute workflow
    E->>P: Store execution state
    E->>N: Send NOTIFY events
    N->>O: Update progress
    E->>AI: Return results
```

### Multi-Instance Coordination

```mermaid
graph TB
    subgraph "Instance 1"
        A1[Pgflow App 1]
        B1[Local Tasks]
    end
    
    subgraph "Instance 2"
        A2[Pgflow App 2]
        B2[Local Tasks]
    end
    
    subgraph "Instance 3"
        A3[Pgflow App 3]
        B3[Local Tasks]
    end
    
    subgraph "Shared Database"
        C[PostgreSQL + pgmq]
        D[Shared Workflow State]
        E[NOTIFY Events]
    end
    
    A1 --> C
    A2 --> C
    A3 --> C
    C --> D
    C --> E
    E --> A1
    E --> A2
    E --> A3
```

These diagrams provide a comprehensive view of the Pgflow architecture, showing how PGMQ + NOTIFY integration works across all layers of the system.