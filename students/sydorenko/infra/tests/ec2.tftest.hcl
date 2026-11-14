mock_provider "aws" {
  mock_data "aws_vpc" {
    defaults = {
      id = "vpc-0123456789abcdef0"
    }
  }

  mock_data "aws_ami" {
    defaults = {
      id = "ami-0123456789abcdef0"
    }
  }

  mock_resource "aws_instance" {
    defaults = {
      id        = "i-0123456789abcdef0"
      public_ip = "192.0.2.20"
    }
  }

  mock_resource "aws_security_group" {
    defaults = {
      id = "sg-0123456789abcdef0"
    }
  }
}

variables {
  key_name = "test-key"
  app_cidr = "192.0.2.10/32"
}

run "plan_ec2" {
  command = plan

  assert {
    condition     = aws_instance.app.key_name == "test-key" && aws_instance.app.associate_public_ip_address
    error_message = "The EC2 plan must use the requested key pair and public IPv4."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.http.cidr_ipv4 == "192.0.2.10/32" && aws_vpc_security_group_ingress_rule.http.from_port == 3000 && aws_vpc_security_group_ingress_rule.http.to_port == 3000
    error_message = "Port 3000 must be limited to the configured IPv4 CIDR."
  }
}

run "apply_with_mock_aws" {
  command = apply

  assert {
    condition     = output.security_group_id == "sg-0123456789abcdef0" && output.app_url == "http://192.0.2.20:3000/"
    error_message = "Deploy must receive the security group ID and the application address."
  }
}
