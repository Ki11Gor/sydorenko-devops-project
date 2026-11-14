variable "aws_region" {
  description = "AWS region for EC2 and the state bucket."
  type        = string
  default     = "us-east-1"
}

variable "ami_id" {
  description = "Ubuntu 24.04 AMD64 AMI. Null selects the current Canonical image."
  type        = string
  default     = null

  validation {
    condition     = var.ami_id == null ? true : can(regex("^ami-([0-9a-f]{8}|[0-9a-f]{17})$", var.ami_id))
    error_message = "Use an EC2 AMI ID or null."
  }
}

variable "key_name" {
  description = "Name of an existing EC2 key pair in the chosen region."
  type        = string
}

variable "app_cidr" {
  description = "IPv4 CIDR allowed to access the API on port 3000."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.app_cidr))
    error_message = "Use an IPv4 CIDR, for example 203.0.113.10/32."
  }
}
