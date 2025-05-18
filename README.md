# 🚀 EC2 EBS Auto-Grow — Fully Reproducible with Terraform

Spin up an Ubuntu EC2 instance that **automatically expands its own root EBS volume** when disk usage hits 90 %.  
No manual resizing, no midnight pages.

[![CI](https://github.com/Bilal31313/ec2-ebs-autogrow/actions/workflows/ci.yml/badge.svg)](https://github.com/Bilal31313/ec2-ebs-autogrow/actions)

---

## ⚡ Quick start

```bash
git clone https://github.com/Bilal31313/ec2-ebs-autogrow.git
cd ec2-ebs-autogrow/terraform
terraform init
terraform apply -var="key_pair_name=<your-key>"
ssh -i <your-key>.pem ubuntu@$(terraform output -raw public_ip)
tail -f /var/log/ebs-monitor.log
```
✅ To clean up:
terraform destroy -auto-approve


🖼️ Architecture at a glance
![image](https://github.com/user-attachments/assets/75f85cf5-4944-4362-8512-16f1e06a0223)


💡 How it works
Layer	Details
Bash script	IMDSv2 → discover instance/volume → aws ec2 modify-volume → growpart + resize2fs
Cron	Runs every 10 min, logs to /var/log/ebs-monitor.log
Terraform	EC2 + IAM + CloudWatch Logs + SNS + user_data bootstrap
CI/CD	GitHub Actions → terraform fmt -check + ShellCheck

📸 Proof-of-life
Before grow	After grow	Alert e-mail
![image](https://github.com/user-attachments/assets/33046b86-f3e4-4fc6-9cf8-eb8d45a75a54)

👨‍💻 Author Bilal Khawaja Cloud Engineer | AWS Certified Solutions Architect – Associate LinkedIn http://www.linkedin.com/in/bilal-khawaja-65b883243 GitHub: @Bilal31313
