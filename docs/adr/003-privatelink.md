# ADR 003: PrivateLink - DESIGN-ONLY

**Date:** 2024-01-15  
**Status:** DESIGN-ONLY  
**Deciders:** Platform Architecture Team  
**Context:** HPC Platform Operations Test Bed  
**Affected Requirements:** 3.4, 16.1, 16.2

---

## Decision

AWS PrivateLink will **NOT** be implemented in the sandbox environment. This feature is DESIGN-ONLY and documented for production reference. The sandbox is limited to gateway endpoints only (S3).

## Context

The sandbox environment uses VPC gateway endpoints for S3 access. PrivateLink enables private connectivity to AWS services, partner services, and self-hosted services without using public IPs or NAT devices.

## Decision Criteria

- **Sandbox constraints:** Only gateway endpoints are supported; PrivateLink requires additional infrastructure
- **Use case:** Sandbox uses S3 gateway endpoint for required services
- **Production target:** PrivateLink used for service mesh and cross-account service access

## Target Design (Production)

### Architecture

```
                      +------------------+
                      |  VPC A           |
                      |  (HPC Service)   |
                      +--------+---------+
                               |
                               | PrivateLink Endpoint
                               | (Interface VPC Endpoint)
                               |
                      +--------+---------+
                      |  VPC Endpoint    |
                      |  Service         |
                      +--------+---------+
                               |
                               | PrivateLink (nlb-xxxx)
                               |
                      +--------+---------+
                      |  VPC B           |
                      |  (Consumer)      |
                      +--------+---------+
```

### Use Cases

1. **Service mesh:** Microservices communication without public endpoints
2. **Cross-account access:** Share services between AWS accounts securely
3. **ISV integration:** Access third-party SaaS services via private connection
4. **Data protection:** Keep traffic off public internet

### Implementation Plan

1. Create Network Load Balancer (NLB) for the service
2. Create VPC endpoint service configuration
3. Configure allowed principals for cross-account access
4. Create interface VPC endpoint in consumer VPC
5. Configure security groups for endpoint access
6. Test connectivity through endpoint

### Security Considerations

- Use VPC endpoint policies to restrict service access
- Implement resource-based policies for endpoint service
- Use AWS RAM for cross-account sharing
- Monitor endpoint access with VPC Flow Logs
- Implement mTLS for service-to-service authentication

## Sandbox Substitute

The sandbox uses:
- VPC gateway endpoints for S3 (as specified in design)
- Security groups for all traffic control
- Public IPs with security controls for external access

## Why Not Build Here

1. **Interface endpoints:** Only gateway endpoints allowed per design requirement 3.2
2. **Cost:** PrivateLink has per-hour and data processing costs
3. **Complexity:** Adds service mesh complexity not needed for sandbox
4. **Scope:** Sandbox demonstrates core platform operations, not service discovery

## Alternatives Considered

### Alternative 1: Gateway Endpoints Only (Selected)
- **Pros:** Simple, no additional cost, meets requirements
- **Cons:** Limited to S3 and DynamoDB

### Alternative 2: Interface Endpoints with PrivateLink
- **Pros:** Private access to AWS services, cross-account sharing
- **Cons:** Higher cost, complexity, requires NLB

### Alternative 3: Public Endpoints with Security Groups
- **Pros:** Simplest approach
- **Cons:** Traffic over public internet, not recommended for production

## Implementation Checklist (Production)

- [ ] Identify services requiring PrivateLink access
- [ ] Create NLBs for each service
- [ ] Configure endpoint service with allowed principals
- [ ] Create interface endpoints in consumer VPCs
- [ ] Configure endpoint policies and security groups
- [ ] Test cross-account access
- [ ] Implement monitoring and logging
- [ ] Document service mesh architecture

## Related Documents

- ADR 001: Transit Gateway
- ADR 002: Direct Connect
- Network Design Document

## References

- [AWS PrivateLink Documentation](https://docs.aws.amazon.com/vpc/latest/privatelink/what-is-privatelink.html)
- [Interface VPC Endpoints](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-endpoints.html)

---

*Last updated: 2024-01-15*
