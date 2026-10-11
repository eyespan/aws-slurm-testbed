# ADR 001: Transit Gateway - DESIGN-ONLY

**Date:** 2024-01-15  
**Status:** DESIGN-ONLY  
**Deciders:** Platform Architecture Team  
**Context:** HPC Platform Operations Test Bed  
**Affected Requirements:** 3.4, 16.1, 16.2

---

## Decision

Transit Gateway will **NOT** be implemented in the sandbox environment. This feature is DESIGN-ONLY and documented for production reference.

## Context

The sandbox environment is a scaled-down Slurm cluster for demonstrating HPC platform operations practices. Transit Gateway is a network transit hub that enables connecting VPCs, on-premises networks, and AWS services.

## Decision Criteria

- **Sandbox constraints:** Transit Gateway has additional costs and complexity not justified for the sandbox
- **Multi-VPC requirement:** Sandbox uses single VPC; Transit Gateway shines in multi-VPC architectures
- **Production target:** Production environments typically use Transit Gateway for hub-and-spoke networking

## Target Design (Production)

### Architecture

```
                      +------------------+
                      | Transit Gateway  |
                      |  (tgw-xxxx)      |
                      +--------+---------+
                               |
               +---------------+---------------+
               |               |               |
         +-----+-----+  +------+-----+  +-----+-----+
         |  VPC A    |  |  VPC B     |  |  On-Prem    |
         |  (HPC)    |  |  (Shared   |  |  VPN/Direct |
         |           |  |  Services) |  |  Connect    |
         +-----------+  +------------+  +-----------+
```

### Use Cases

1. **Hub-and-spoke networking:** Single VPC as hub, multiple spoke VPCs
2. **Shared services VPC:** Centralized DNS, logging, security scanning
3. **Hybrid cloud:** Combine with Direct Connect for on-prem connectivity

### Implementation Plan

1. Create Transit Gateway with routing domain configuration
2. Configure VPC attachments with route table associations
3. Set up route propagation from VPCs to TGW
4. Configure VPN attachments for on-premises connectivity
5. Implement TGW Flow Logs for monitoring

### Security Considerations

- Enable TGW Flow Logs to CloudWatch for audit trail
- Use separate route tables for different traffic types
- Implement security groups and NACLs at VPC level
- Monitor for unauthorized VPC attachments

## Sandbox Substitute

The sandbox uses a single VPC with:
- Public and private subnets across 2 AZs
- NAT gateway for outbound internet access
- Security groups for tier-based access control
- Route tables for subnet routing

## Why Not Build Here

1. **Cost:** Transit Gateway adds $0.05/hour plus data processing fees
2. **Complexity:** Adds configuration complexity not needed for sandbox
3. **Scope:** Sandbox demonstrates platform operations, not multi-VPC networking
4. **Time:** Multi-VPC setup requires additional VPCs not in budget

## Alternatives Considered

### Alternative 1: Single VPC (Selected)
- **Pros:** Simple, low cost, meets sandbox requirements
- **Cons:** Limited scalability, no network segmentation

### Alternative 2: Multi-VPC with Transit Gateway
- **Pros:** Realistic production architecture, better segmentation
- **Cons:** High cost, complex setup, beyond sandbox scope

### Alternative 3: Local Network with Direct Connect
- **Pros:** Direct on-prem connectivity, low latency
- **Cons:** Requires physical connection, high cost

## Implementation Checklist (Production)

- [ ] Design routing domains and route table structure
- [ ] Create Transit Gateway with appropriate settings
- [ ] Configure VPC attachments with route table associations
- [ ] Set up VPN attachments for on-premises connectivity
- [ ] Configure route propagation and static routes
- [ ] Implement TGW Flow Logs
- [ ] Test cross-VPC connectivity
- [ ] Document routing and security rules

## Related Documents

- ADR 002: Direct Connect
- ADR 003: PrivateLink
- Network Design Document
- Sandbox Constraints Document

## References

- [AWS Transit Gateway Documentation](https://docs.aws.amazon.com/transit-gateway/latest/overview/what-is-transit-gateway.html)
- [Transit Gateway Best Practices](https://aws.amazon.com/transit-gateway/faqs/)

---

*Last updated: 2024-01-15*
