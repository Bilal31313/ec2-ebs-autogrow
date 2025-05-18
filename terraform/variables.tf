variable "aws_region" {
  description = "AWS region to deploy to"
  default     = "eu-west-2"
}

variable "instance_type" {
  description = "EC2 instance size"
  default     = "t3.micro"
}

variable "key_pair_name" {
  description = "Existing EC2 key pair name for SSH"
  type        = string
}
