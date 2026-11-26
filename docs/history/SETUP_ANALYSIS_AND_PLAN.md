# Rails Setup Analysis and Implementation Plan

## Current Situation (2025-01-27)

### Problem Summary
The `setup_rails.sh` script in `/workspaces/dockercrap/archive/` is failing due to Ruby/Bundler compatibility issues in a WSL2 containerized environment.

### Root Cause Analysis

#### Primary Issue: Ruby/Bundler Version Compatibility
- **Ruby Version**: 3.3.8p144 (managed by `mise`)
- **Bundler Version**: 2.5.22
- **Error**: `FrozenError: can't modify frozen File` in RubyGems vendor directory
- **Location**: `/home/vscode/.local/share/mise/installs/ruby/3.3.8/lib/ruby/3.3.0/rubygems/vendor/uri/lib/uri/common.rb`

#### Secondary Issues
1. **Directory Context**: Script assumes fresh Rails setup but working with existing Rails app
2. **Database Dependencies**: No verification of PostgreSQL availability/configuration
3. **Error Handling**: Script fails completely on first gem installation error
4. **Environment Assumptions**: Relies on global Ruby installation without proper isolation

### Current Environment Details
- **OS**: Linux 6.6.87.2-microsoft-standard-WSL2
- **Shell**: /bin/bash
- **Working Directory**: /workspaces/dockercrap/archive
- **Ruby Manager**: mise (formerly rtx)
- **Container**: VS Code devcontainer environment

### Files Involved
- **Main Script**: `archive/setup_rails.sh` (82 lines)
- **Gem Setup**: `archive/setup_gems.rb` (31 lines)
- **Rails App**: Existing Rails application in `/workspaces/dockercrap/jukebox/`
- **Gemfile**: Present in archive directory with Rails 8.0.2

## Implementation Strategy

### Phase 1: Immediate Stability (Priority 1)
1. **Pin Ruby to 3.2.x** - More stable than 3.3.x
2. **Use Bundler 2.4.x** - Avoid 2.5.x compatibility issues
3. **Implement proper error handling** in setup script
4. **Add health checks** and validation steps

### Phase 2: Robust Foundation (Priority 2)
1. **Multi-stage Docker builds**
2. **Pre-built gem installation**
3. **Environment-specific configurations**
4. **Comprehensive logging and monitoring**

### Phase 3: Production Readiness (Priority 3)
1. **Automated testing pipeline**
2. **Security scanning integration**
3. **Performance optimization**
4. **Disaster recovery procedures**

## Technical Recommendations

### Version Pinning Strategy
```bash
# Target versions for stability:
- Ruby: 3.2.4 (stable, well-tested)
- Bundler: 2.4.22 (avoid 2.5.x issues)
- Rails: 8.0.2 (current version)
```

### Container Architecture
```bash
# Multi-stage approach:
1. Base Layer: OS + Ruby runtime (pinned versions)
2. Dependency Layer: System packages (PostgreSQL client, etc.)
3. Application Layer: Rails app with pre-built gems
4. Runtime Layer: Application-specific configurations
```

### Dependency Management
```bash
# Pre-build strategy:
- Install gems during container build
- Use `bundle config set --local deployment 'true'`
- Vendor gems in the container
- Use `bundle exec` for all Rails commands
```

## Risk Mitigation

### High-Risk Areas
1. **Ruby version compatibility** - Pin to stable versions
2. **Gem installation reliability** - Pre-build in containers
3. **Database dependency** - Implement proper connection handling
4. **Environment-specific issues** - Use configuration management

### Monitoring Points
1. **Setup success rates** by environment
2. **Gem installation times** and failure rates
3. **Database connection reliability**
4. **Container build times** and success rates

## Implementation Checklist

### Before Starting
- [ ] Backup current working state
- [ ] Document current gem versions
- [ ] Identify all Rails commands that need to work
- [ ] Map out database dependencies

### Phase 1 Tasks
- [ ] Create new Ruby version specification
- [ ] Update Bundler version
- [ ] Modify setup script with better error handling
- [ ] Add validation steps
- [ ] Test in isolated environment

### Phase 2 Tasks
- [ ] Design multi-stage Dockerfile
- [ ] Implement gem pre-building
- [ ] Create environment-specific configs
- [ ] Add comprehensive logging
- [ ] Test deployment pipeline

### Phase 3 Tasks
- [ ] Implement automated testing
- [ ] Add security scanning
- [ ] Optimize performance
- [ ] Create disaster recovery procedures

## Current Working State

### What Works
- Rails application structure exists in `/workspaces/dockercrap/jukebox/`
- Basic Rails setup with Gemfile and Gemfile.lock
- PostgreSQL development libraries installed
- Basic container environment functional

### What's Broken
- `setup_rails.sh` script fails on gem installation
- Ruby 3.3.8 + Bundler 2.5.22 compatibility issues
- No proper error handling or rollback mechanisms
- Database setup not verified

### Files to Reference
- **Current Analysis**: This document (`SETUP_ANALYSIS_AND_PLAN.md`)
- **Original Script**: `archive/setup_rails.sh`
- **Gem Setup**: `archive/setup_gems.rb`
- **Rails App**: `/workspaces/dockercrap/jukebox/`
- **Error Logs**: Terminal output from failed script execution

## Next Steps

1. **Begin Phase 1 implementation** - Focus on immediate stability
2. **Test each change** in isolated environment
3. **Document all modifications** for future reference
4. **Create rollback procedures** for each phase
5. **Implement monitoring** to track success rates

## Success Criteria

### Phase 1 Success
- [ ] Setup script runs without frozen file errors
- [ ] All Rails commands execute successfully
- [ ] Database operations work correctly
- [ ] Gem installation is reliable

### Phase 2 Success
- [ ] Container builds consistently
- [ ] Deployment is automated and reliable
- [ ] Environment-specific configs work
- [ ] Logging provides clear troubleshooting info

### Phase 3 Success
- [ ] Automated testing catches issues
- [ ] Security scanning integrated
- [ ] Performance meets requirements
- [ ] Disaster recovery procedures tested

---

**Document Reference**: If context is lost, refer to this document (`SETUP_ANALYSIS_AND_PLAN.md`) to understand the current situation and continue implementation from the appropriate phase. 