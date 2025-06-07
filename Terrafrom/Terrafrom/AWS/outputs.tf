output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "load_balancer_dns_name" {
  value = aws_lb.ec2_alb.dns_name
}
