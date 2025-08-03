# Business Central with Containerized SQL - Execution Flow

## System Architecture Overview

```mermaid
flowchart TB
    subgraph Docker_Environment["Docker Environment"]
        subgraph BC_Container["BC Container (Ubuntu + Wine)"]
            BC_Wine["Wine Environment"]
            BC_Server["BC Server.exe"]
            BC_Config["CustomSettings.config"]
            BC_Artifacts["BC Artifacts Volume"]
        end
        
        subgraph SQL_Container["SQL Container"]
            SQL_Server["SQL Server 2022"]
            SQL_DB["BC Database"]
            BC_Artifacts_RO["BC Artifacts Volume (Read-Only)"]
        end
        
        subgraph Shared_Network["bc-network (Bridge)"]
            Network_Bridge["Docker Bridge Network"]
        end
    end
    
    BC_Server -->|"SQL Connection<br/>Server: sql<br/>Database: BC"| Network_Bridge
    Network_Bridge --> SQL_Server
    BC_Artifacts -.->|"Shared Volume"| BC_Artifacts_RO
    BC_Config -->|"Configuration"| BC_Server
    BC_Wine -->|"Hosts"| BC_Server
    SQL_Server -->|"Manages"| SQL_DB
    
    style BC_Container fill:#e1f5fe,stroke:#01579b,stroke-width:2px
    style SQL_Container fill:#fce4ec,stroke:#880e4f,stroke-width:2px
    style Shared_Network fill:#f3e5f5,stroke:#4a148c,stroke-width:2px
```

## Container Startup Sequence with Database Restoration

```mermaid
flowchart TD
    A[docker compose up] --> B[SQL Container Starts]
    A --> C[BC Container Waits]
    
    B --> D[SQL Server Initializes]
    D --> E[SQL Health Check]
    E -->|Healthy| F[SQL Container Ready]
    
    F --> G[BC Container Starts]
    G --> H[entrypoint.sh]
    
    H --> I{First Run?}
    I -->|Yes| J[init-wine.sh]
    I -->|No| K[Skip Wine Init]
    
    J --> L[Install Wine Components]
    L --> M[Install .NET Framework]
    M --> N[Create Encryption Keys]
    N --> O[Touch .wine-initialized]
    
    O --> P[Restore Database Check]
    K --> P
    
    P --> Q[restore-database.sh]
    Q --> R{BC Database Exists?}
    
    R -->|No| S[Copy Backup to Shared Volume]
    R -->|Yes| T[Skip Restore]
    
    S --> U[SQL Server Reads Backup]
    U --> V[Restore BC Database]
    V --> W[Database Online]
    
    W --> X[start-bcserver.sh]
    T --> X
    
    X --> Y[Configure BC Server]
    Y --> Z[Copy CustomSettings.config]
    Z --> AA[Copy Encryption Keys]
    AA --> AB[Start BC Server.exe]
    
    AB --> AC[BC Server Running]
    AC --> AD[Endpoints Available]
    
    style A fill:#f9f,stroke:#333,stroke-width:4px
    style F fill:#9f9,stroke:#333,stroke-width:2px
    style W fill:#9f9,stroke:#333,stroke-width:2px
    style AC fill:#9f9,stroke:#333,stroke-width:4px
    style Q fill:#ff9,stroke:#333,stroke-width:2px
```

## Database Restoration Flow Detail

```mermaid
flowchart LR
    subgraph Restore_Process["Database Restoration Process"]
        A[restore-database.sh] --> B[Check SQL Connectivity]
        B --> C{SQL Ready?}
        C -->|No| D[Wait & Retry]
        D --> B
        C -->|Yes| E[Check if BC Database Exists]
        
        E --> F{Database Exists?}
        F -->|Yes| G[Exit - No Restore Needed]
        F -->|No| H[Check Backup File]
        
        H --> I{Backup Found?}
        I -->|No| J[Create Empty Database]
        I -->|Yes| K[Read Backup Metadata]
        
        K --> L[Extract Logical File Names]
        L --> M[Execute RESTORE DATABASE]
        M --> N[Verify Database State]
        N --> O[Database Ready]
    end
    
    subgraph File_Access["Shared Volume Access"]
        P["/home/bcartifacts/BusinessCentral-W1.bak<br/>(BC Container)"]
        Q["/bc_artifacts/BusinessCentral-W1.bak<br/>(SQL Container - Read Only)"]
        P -.->|"Docker Volume Mount"| Q
    end
    
    K --> Q
    M --> Q
    
    style O fill:#9f9,stroke:#333,stroke-width:2px
    style G fill:#99f,stroke:#333,stroke-width:2px
```

## Network Communication Flow

```mermaid
flowchart TD
    subgraph External["External Access"]
        Client[Client Applications]
    end
    
    subgraph Host_Ports["Host Machine Ports"]
        P1[":7046 (Client Services)"]
        P2[":7047 (SOAP Services)"]
        P3[":7048 (OData Services)"]
        P4[":7049 (Development)"]
        P5[":1433 (SQL Server)"]
    end
    
    subgraph Container_Network["Docker Network: bc-network"]
        BC_Int["BC Container<br/>Hostname: bc"]
        SQL_Int["SQL Container<br/>Hostname: sql"]
    end
    
    Client --> P1
    Client --> P2
    Client --> P3
    Client --> P4
    Client --> P5
    
    P1 --> BC_Int
    P2 --> BC_Int
    P3 --> BC_Int
    P4 --> BC_Int
    P5 --> SQL_Int
    
    BC_Int -->|"Internal SQL Connection<br/>sql:1433"| SQL_Int
    
    style Client fill:#fff,stroke:#333,stroke-width:2px
    style Container_Network fill:#f3e5f5,stroke:#4a148c,stroke-width:2px
```

## Key Configuration Changes

### CustomSettings.config
```xml
<!-- Old Configuration (Host Database) -->
<add key="DatabaseServer" value="192.168.2.99" />
<add key="DatabaseName" value="bc4ubuntu" />

<!-- New Configuration (Containerized SQL) -->
<add key="DatabaseServer" value="sql" />
<add key="DatabaseName" value="BC" />
```

### Docker Compose Volume Configuration
```yaml
sql:
  volumes:
    - sql_data:/var/opt/mssql
    - bc_artifacts:/bc_artifacts:ro  # Added for database restore

bc:
  volumes:
    - bc_artifacts:/home/bcartifacts  # Contains backup file
```

## Critical Components

### 1. **SQL Container Health Check**
- Ensures SQL Server is ready before BC container starts
- Uses sqlcmd to verify connectivity
- Prevents race conditions during startup

### 2. **Database Restoration Script**
- Automatically runs on container startup
- Checks if database exists before attempting restore
- Uses shared volume for backup file access
- Handles both new deployments and container restarts

### 3. **Network Configuration**
- Both containers on same Docker network
- BC container references SQL by hostname "sql"
- No hardcoded IP addresses
- Fully portable solution

### 4. **Wine Custom Build**
- Includes patches for locale/culture issues
- Supports .NET Framework and BC Server
- Multi-stage build for efficiency

## Service Endpoints

| Service | Port | URL | Purpose |
|---------|------|-----|---------|
| OData | 7048 | http://localhost:7048/BC/OData | Data API |
| SOAP | 7047 | http://localhost:7047/BC/WS/ | Web Services |
| Development | 7049 | http://localhost:7049/BC/dev/ | Development Endpoint |
| Client Services | 7046 | - | Windows Client Connection |
| SQL Server | 1433 | localhost:1433 | Direct SQL Access |

## Troubleshooting Connection Points

1. **BC to SQL Connection**
   - Check: `docker exec bcdevonlinux-bc-1 /opt/mssql-tools18/bin/sqlcmd -S sql -U sa -P P@ssw0rd123! -Q "SELECT 1" -C`
   - Verify network: `docker network inspect bcdevonlinux_bc-network`

2. **Database Restore Issues**
   - Check backup file: `docker exec bcdevonlinux-bc-1 ls -la /home/bcartifacts/`
   - Check SQL access: `docker exec bcdevonlinux-sql-1 ls -la /bc_artifacts/`
   - Manual restore: `docker exec bcdevonlinux-bc-1 /home/restore-database.sh`

3. **BC Server Status**
   - Check process: `docker exec bcdevonlinux-bc-1 ps aux | grep Nav.Server`
   - View logs: `docker logs bcdevonlinux-bc-1`

## Success Criteria

- ✅ SQL Container healthy
- ✅ BC Container healthy
- ✅ Database restored (3648 tables)
- ✅ BC Server process running
- ✅ All endpoints responding
- ✅ No external dependencies
- ✅ Fully containerized solution