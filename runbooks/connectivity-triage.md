# Network Connectivity Diagnostic Runbook

**Purpose:** Diagnose and resolve common network connectivity issues in the HPC Platform Operations Test Bed.

**Trigger:** User reports inability to access cluster resources, SSH failures, job submission failures, or DNS resolution failures.

**Impact:** Users cannot access the cluster, submit jobs, or access shared storage. Service availability is impacted.

---

## 1. Diagnosis Checklist

Follow this checklist in order. Each step should take no more than 10 minutes. If a step doesn't identify the issue, move to the next.

### 1.1 Verify User Access and SSH

**Objective:** Confirm the user can reach the login node.

**Commands:**
```bash
# From local machine
ssh -v username@login-node-public-dns

# On the login node, verify SSH is running
sudo systemctl status sshd

# Check if SSH port is listening
sudo ss -tlnp | grep :22
```

**Expected:** SSH daemon is running and listening on port 22.

**If fails:**
- Check Security Groups (Section 1.2)
- Check NACLs (Section 1.3)
- Check login node instance state

### 1.2 Security Groups Verification

**Objective:** Verify security groups allow required traffic.

**Checklist:**

| Source | Destination | Port | Protocol | Expected Rule |
|---|---|---|---|---|
| 0.0.0.0/0 | Login Node SG | 22 (SSH) | TCP | Allow |
| 0.0.0.0/0 | Login Node SG | 80/443 (Portal) | TCP | Allow |
| Login SG | Controller SG | 22 (SSH) | TCP | Allow |
| Login SG | Controller SG | 6817 (Slurmctld) | TCP | Allow |
| Controller SG | Compute SG | 6818 (Slurmd) | TCP | Allow |
| Compute SG | EFS SG | 2049 (NFS) | TCP | Allow |
| All SGs | EFS SG | 2049 (NFS) | TCP | Allow |

**Commands:**
```bash
# Get security group IDs from Terraform state or AWS Console
aws ec2 describe-security-groups --filters "Name=vpc-id,Values=<vpc-id>" --query 'SecurityGroups[?contains(Tags[?Key==`Name`].Value, `login`)].{Name:Tags[?Key==`Name`].Value[0], GroupId:GroupId}'

# Verify rules
aws ec2 describe-security-group-rules --security-group-ids <sg-id>
```

**Expected:** All required rules are present and allow the specified traffic.

**If fails:**
- Add missing rules via Terraform or AWS Console
- Verify VPC CIDR blocks match expected ranges
- Check for rule ordering issues (though AWS processes all rules)

### 1.3 NACLs Verification

**Objective:** Verify Network Access Control Lists don't block traffic.

**Checklist:**

| Subnet Type | Inbound Rule | Outbound Rule |
|---|---|---|
| Public | Allow 0.0.0.0/0 SSH (22), HTTP (80), HTTPS (443) | Allow All Traffic |
| Private | Allow VPC CIDR SSH (22), All Ephemeral (1024-65535) | Allow All Traffic |

**Commands:**
```bash
# Get NACL ID from subnet
aws ec2 describe-subnets --subnet-ids <subnet-id> --query 'Subnets[].NetworkAclId'

# Check NACL rules
aws ec2 describe-network-acls --network-acl-ids <nacl-id>
```

**Expected:**
- Public subnet NACL allows SSH, HTTP, HTTPS inbound
- Private subnet NACL allows SSH and ephemeral ports inbound
- Both subnets NACLs allow all outbound traffic

**If fails:**
- NACLs are stateless; both directions must be explicitly allowed
- Default deny rule at the end must not block the traffic
- Rule numbers matter; lower numbers process first

### 1.4 Route Table Verification

**Objective:** Verify routes allow traffic to flow between subnets and to the internet.

**Public Subnet Routes:**
```
Destination: 0.0.0.0/0 -> Target: igw-xxxx (Internet Gateway)
```

**Private Subnet Routes:**
```
Destination: 0.0.0.0/0 -> Target: nat-xxxx (NAT Gateway)
```

**Inter-subnet Routes:**
```
Destination: <vpc-cidr> -> Target: local
```

**Commands:**
```bash
# Get route tables
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=<vpc-id>"

# Verify specific route table
aws ec2 describe-route-tables --route-table-ids <rt-id>
```

**Expected:**
- Public route table has route to IGW for 0.0.0.0/0
- Private route table has route to NAT gateway for 0.0.0.0/0
- Both have local route for VPC CIDR

**If fails:**
- Check route table associations
- Verify NAT gateway is in correct subnet
- Ensure NAT gateway has an EIP and is available

### 1.5 DNS Resolution

**Objective:** Verify DNS resolution works within the VPC.

**Test DNS for login node:**
```bash
# On any node in the VPC
nslookup login.hpc.internal
dig login.hpc.internal

# Test external DNS
nslookup google.com
```

**Expected:**
- Internal DNS (login.hpc.internal, controller.hpc.internal) resolves to private IPs
- External DNS resolves correctly

**If internal DNS fails:**
- Verify Route 53 private hosted zone exists: `aws route53 list-hosted-zones --query 'HostedZones[?Name==`hpc.internal`]'`
- Verify VPC association: `aws route53 get-hosted-zone --id <zone-id> --query 'HostedZone.VPCs'`
- Check DNS attributes on VPC: `aws ec2 describe-vpc-attribute --vpc-id <vpc-id> --attribute enableDnsSupport --query 'EnableDnsSupport.Value'`
- Check DNS hostnames: `aws ec2 describe-vpc-attribute --vpc-id <vpc-id> --attribute enableDnsHostnames --query 'EnableDnsHostnames.Value'`

**If external DNS fails:**
- Verify NAT gateway is working (check CloudWatch metrics: NATGatewayBytes)
- Check if instance has public IP (for public subnet instances)
- Verify security groups allow outbound DNS (port 53 UDP/TCP)

### 1.6 Flow Logs Analysis

**Objective:** Analyze VPC Flow Logs to identify blocked or unusual traffic.

**Check for denied traffic:**
```bash
# Get flow log group name from Terraform outputs or state
aws logs describe-log-groups --log-group-name-prefix "/aws/vpc/flow_logs"

# Query flow logs for rejected traffic (example with CloudWatch Insights)
aws logs start-query \
  --log-group-name "<flow-log-group>" \
  --start-time $(date -d '1 hour ago' +%s) \
  --end-time $(date +%s) \
  --query-string 'FILTER action = "REJECT" | stats count(*) as rejected_count by srcAddr, dstAddr, dstPort, protocol'
```

**Expected:**
- Minimal rejected traffic (only intentional firewall rules)
- Expected traffic patterns match architecture

**Interpretation:**
- High reject count from specific sources: Check NACLs and security groups
- Traffic to unexpected destinations: Review for potential misconfiguration or security issues
- No traffic at all: Verify flow logs are enabled and the traffic is actually occurring

---

## 2. Common Issues and Resolution

### Issue: Cannot SSH to Login Node

**Symptoms:** SSH connection times out or is refused.

**Quick Fix:**
1. Check login node instance state: `aws ec2 describe-instances --instance-ids <instance-id>`
2. Verify security group allows SSH (0.0.0.0/0 on port 22)
3. Verify route table has IGW route for 0.0.0.0/0
4. Verify NACL allows inbound/outbound SSH

### Issue: Login Node Cannot Reach Controller

**Symptoms:** SSH from login to controller fails.

**Quick Fix:**
1. Verify controller security group allows SSH from login SG
2. Verify controller has an IP in the private subnet
3. Check route table for private subnet has local route

### Issue: Compute Nodes Cannot Mount EFS

**Symptoms:** `mount` command fails or times out.

**Quick Fix:**
1. Verify EFS security group allows NFS (port 2049) from VPC CIDR
2. Verify mount targets exist in both AZs: `aws efs describe-mount-targets --file-system-id <efs-id>`
3. Check that mount target has a private IP
4. Verify security groups on compute nodes allow outbound NFS

### Issue: DNS Resolution Fails

**Symptoms:** `nslookup` or `dig` returns NXDOMAIN or times out.

**Quick Fix:**
1. Verify VPC DNS support is enabled
2. Verify VPC DNS hostnames is enabled
3. Verify Route 53 private hosted zone is associated with VPC
4. Check instance `/etc/resolv.conf` has correct nameserver (10.0.0.2 for default VPC)

### Issue: Internet Access Fails from Private Subnet

**Symptoms:** Instances in private subnet cannot reach internet (yum update, pip install, etc.)

**Quick Fix:**
1. Verify NAT gateway is in available state: `aws ec2 describe-nat-gateways --nat-gateway-ids <nat-id>`
2. Verify NAT gateway has an EIP
3. Verify private route table routes 0.0.0.0/0 to NAT gateway
4. Check NAT gateway CloudWatch metrics for bytes processed

---

## 3. Escalation

If the issue persists after following the diagnostic steps:

1. Gather evidence:
   ```bash
   # VPC details
   aws ec2 describe-vpcs --vpc-ids <vpc-id>
   aws ec2 describe-subnets --filters "Name=vpc-id,Values=<vpc-id>"
   
   # Security groups
   aws ec2 describe-security-groups --filters "Name=vpc-id,Values=<vpc-id>"
   
   # Route tables
   aws ec2 describe-route-tables --filters "Name=vpc-id,Values=<vpc-id>"
   
   # NAT gateway status
   aws ec2 describe-nat-gateways --filters "Name=vpc-id,Values=<vpc-id>"
   
   # Flow logs (last hour)
   aws logs filter-log-events --log-group-name "<flow-log-group>" --start-time $(date -d '1 hour ago' +%s)000 --max-events 100
   ```

2. Create a GitHub issue or Jira ticket with:
   - VPC ID
   - Affected resources (instance IDs, IPs)
   - Error messages
   - Evidence gather above

3. Escalate to platform engineer with sandbox access.

---

## 4. Evidence Collection

After resolving the issue, document:

- Root cause
- Steps taken
- Time to resolution
- Any process improvements

Update `docs/sandbox-notes.md` with any new findings or limitations discovered.

---

## 5. Prevention

- Use Terraform to manage all network resources (no console changes)
- Enable VPC Flow Logs to CloudWatch for audit trail
- Document any manual exceptions in `docs/sandbox-notes.md`
- Run `make preflight` before deployments to validate configuration
- Review security groups quarterly for over-permissive rules

---

## 6. References

- AWS VPC Documentation: https://docs.aws.amazon.com/vpc/
- Security Group Rules: https://docs.aws.amazon.com/vpc/latest/userguide/vpc-security-groups.html
- NACLs: https://docs.aws.amazon.com/vpc/latest/userguide/vpc-network-acls.html
- Route Tables: https://docs.aws.amazon.com/vpc/latest/userguide/VPC_Route_Tables.html
- DNS in VPC: https://docs.aws.amazon.com/vpc/latest/userguide/vpc-dns.html

---

*Last updated: $(date +%Y-%m-%d)*
