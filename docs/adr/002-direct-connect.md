# ADR 002: Direct Connect - DESIGN-ONLY

**Date:** 2024-01-15  
**Status:** DESIGN-ONLY  
**Deciders:** Platform Architecture Team  
**Context:** HPC Platform Operations Test Bed  
**Affected Requirements:** 3.4, 16.1, 16.2

---

## Decision

AWS Direct Connect will **NOT** be implemented in the sandbox environment. This feature is DESIGN-ONLY and documented for production reference.

## Context

The sandbox environment uses internet-based connectivity for all network access. Direct Connect provides dedicated network connections from on-premises infrastructure to AWS.

## Decision Criteria

- **Sandbox constraints:** Direct Connect requires physical infrastructure and is not available in sandbox
- **Cost:** Direct Connect has significant setup and monthly costs
- **Use case:** Sandbox focuses on AWS-native operations, not hybrid connectivity

## Target Design (Production)

### Architecture

```
                      +------------------+
                      |  On-Premise      |
                      |  Data Center     |
                      |  (Office/DC)     |
                      +--------+---------+
                               |
                               | Dedicated Circuit
                               | (1 Gbps or 10 Gbps)
                               |
                      +--------+---------+
                      |  Direct Connect  |
                      |  Gateway (dx-gw) |
                      +--------+---------+
                               |
                               | Virtual Interface
                               | (Private or Public)
                               |
                      +--------+---------+
                      |  Direct Connect  |
                      |  Link (dx-link)  |
                      +--------+---------+
                               |
                               | Private Virtual Interface
                               |
                      +--------+---------+
                      |  Transit Gateway |
                      |  (for multi-VPC) |
                      +------------------+
```

### Use Cases

1. **Hybrid cloud:** Connect on-premises data center to AWS
2. **High bandwidth:** Transfer large datasets (research data, images)
3. **Consistent performance:** Avoid internet variability
4. **Compliance:** Dedicated connection for regulated workloads

### Implementation Plan

1. Request Direct Connect connection from AWS
2. Configure cross-connect at Direct Connect location
3. Create private or public virtual interface
4. Configure BGP peering for routing
5. Associate with Transit Gateway or direct VPC attachment
6. Implement BGP route filtering and security

### Security Considerations

- Use private virtual interfaces for VPC connectivity
- Implement BGP route authentication (MD5)
- Configure route filtering and prefix limits
- Monitor BGP session health
- Use Direct Connect Gateway for multi-account setups

## Sandbox Substitute

The sandbox uses internet-based connectivity:
- Public subnets with NAT gateway for outbound
- Security groups for access control
- VPN for remote administrative access

## Why Not Build Here

1. **Infrastructure requirements:** Requires physical connection to AWS Direct Connect location
2. **Cost:** $150/month per 1 Gbps port + cross-connect fees
3. **Time:** Setup takes weeks for provisioning
4. **Sandbox limitations:** AWS sandbox doesn't support Direct Connect provisioning

## Alternatives Considered

### Alternative 1: Internet-based (Selected)
- **Pros:** No infrastructure, instant setup, low cost
- **Cons:** Variable performance, security over public internet

### Alternative 2: Direct Connect
- **Pros:** Dedicated, consistent performance, lower latency
- **Cons:** High cost, infrastructure requirements, long setup time

### Alternative 3: VPN over Internet
- **Pros:** Encrypted, can be set up quickly
- **Cons:** Variable performance, bandwidth limits

## Implementation Checklist (Production)

- [ ] Assess bandwidth requirements and choose port speed
- [ ] Contact AWS sales for Direct Connect quote
- [ ] Coordinate cross-connect at Direct Connect location
- [ ] Create Direct Connect gateway
- [ ] Configure virtual interfaces
- [ ] Set up BGP peering
- [ ] Configure route propagation
- [ ] Implement monitoring and alerting
- [ ] Test connectivity and performance

## Related Documents

- ADR 001: Transit Gateway
- ADR 003: PrivateLink
- Network Design Document

## References

- [AWS Direct Connect Documentation](https://docs.aws.amazon.com/directconnect/latest/UserGuide/what-is.html)
- [Direct Connect Pricing](https://aws.amazon.com/directconnect/pricing/)

---

*Last updated: 2024-01-15*
