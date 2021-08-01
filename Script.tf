resource "aws_vpc" "main" {
    cidr_block = "10.0.0.0/16"

    tags = {
        Name = "Project_AutoScaling"
    }
}

resource "aws_internet_gateway" "IG_Pub" {
    vpc_id = "${aws_vpc.main.id}"

    tags = {
        Name = "Ig_Pub"
    }
}

resource "aws_route_table" "Internet_Gateway" {
    vpc_id = "${aws_vpc.main.id}"

    route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.IG_Pub.id}"
    }

    tags = {
        Name = "Internet_Gateway"
    }
}

resource "aws_subnet" "Pub_Network-PROD" {
    vpc_id = "${aws_vpc.main.id}"
    cidr_block = "10.0.0.0/24"
    availability_zone = "eu-west-3a"
    map_public_ip_on_launch = true

    tags = {
        Name = "Public-FRONT"
    }
}


resource "aws_subnet" "Pub_Network-BACK" {
    vpc_id = "${aws_vpc.main.id}"
    cidr_block = "10.0.1.0/24"
    availability_zone = "eu-west-3b"
    map_public_ip_on_launch = true

    tags = {
        Name = "Public-BACK"
    }
}


resource "aws_route_table_association" "Public_route1" {
    subnet_id = "${aws_subnet.Pub_Network-PROD.id}"
    route_table_id = "${aws_route_table.Internet_Gateway.id}"
}


resource "aws_route_table_association" "Public_route2" {
    subnet_id = "${aws_subnet.Pub_Network-BACK.id}"
    route_table_id = "${aws_route_table.Internet_Gateway.id}"
}


resource "aws_security_group" "SG_WEB" {
    name = "SG_Public"
    description = "SG_Public"
    vpc_id = "${aws_vpc.main.id}"

    tags = {
        Name = "SG_Public"
    }
}

resource "aws_security_group_rule" "ingress_rules_Pub" {
    count = length(var.ingress_rules_Pub)

    type              = "ingress"
    from_port         = var.ingress_rules_Pub[count.index].from_port
    to_port           = var.ingress_rules_Pub[count.index].to_port
    protocol          = var.ingress_rules_Pub[count.index].protocol
    cidr_blocks       = [var.ingress_rules_Pub[count.index].cidr_block]
    description       = var.ingress_rules_Pub[count.index].description
    security_group_id = aws_security_group.SG_WEB.id
}

resource "aws_security_group_rule" "egress_rules_Pub" {
    count = length(var.ingress_rules_Pub)

    type              = "egress"
    from_port         = var.egress_rules_Pub[count.index].from_port
    to_port           = var.egress_rules_Pub[count.index].to_port
    protocol          = var.egress_rules_Pub[count.index].protocol
    cidr_blocks       = [var.egress_rules_Pub[count.index].cidr_block]
    description       = var.egress_rules_Pub[count.index].description
    security_group_id = aws_security_group.SG_WEB.id
}

resource "aws_launch_template" "web" {
    name = "web-Template"
    image_id = "ami-0f7cd40eac2214b37"
    instance_type = "t2.micro"
    key_name = "AWS"
    default_version = "1.0"

    network_interfaces {
        security_groups = ["${aws_security_group.SG_WEB.id}"]
        subnet_id   = "${aws_subnet.Pub_Network-PROD.id}"
    }

    monitoring {
      enabled = true
    }

    user_data = filebase64("./myscript.sh")
}

resource "aws_instance" "EC2_WEB" {

    launch_template {
        id = "${aws_launch_template.web.id}" 
        version = "$Latest"     
    }

    tags = {
      Name = "Server_Web1"
    }
}


resource "aws_instance" "EC2_WEB2" {

        launch_template {
        id = "${aws_launch_template.web.id}" 
        version = "$Latest"     
    }

    tags = {
      Name = "Server_Web2"
    }
}



resource "aws_lb_target_group" "front_end" {
    name = "tg-front-end"
    port = 80
    protocol = "HTTP"
    target_type = "instance"
    vpc_id = "${aws_vpc.main.id}"
}

resource "aws_lb_target_group_attachment" "tg_group_attachment1" {
    target_group_arn = "${aws_lb_target_group.front_end.arn}"
    target_id = "${aws_instance.EC2_WEB.id}"
    port = 80
}


resource "aws_lb_target_group_attachment" "tg_group_attachment2" {
    target_group_arn = "${aws_lb_target_group.front_end.arn}"
    target_id = "${aws_instance.EC2_WEB2.id}"
    port = 80
}



resource "aws_lb" "Loadbalancer" {
    name = "Loadbalancer-Web"
    internal = false
    load_balancer_type = "application"
    security_groups = ["${aws_security_group.SG_WEB.id}"]
 
    subnets = [
        "${aws_subnet.Pub_Network-PROD.id}",
        "${aws_subnet.Pub_Network-BACK.id}",
    ]

    tags = {
        Name = "Loadbalancer_Web"
    }
}

resource "aws_lb_listener" "front_end" {
    load_balancer_arn = aws_lb.Loadbalancer.arn
    port = 80
    protocol = "HTTP"

    default_action {
        type = "forward"
        target_group_arn = "${aws_lb_target_group.front_end.arn}"
    }
}


resource "aws_autoscaling_group" "autoScalingGroup" {
    name = "${aws_launch_template.web.name}-asg"
    min_size = 2
    desired_capacity = 2
    max_size = 2
    health_check_type = "ELB"
    health_check_grace_period = 120
    target_group_arns = ["${aws_lb_target_group.front_end.arn}"]
    
    vpc_zone_identifier = [
        aws_subnet.Pub_Network-BACK.id
    ]

    launch_template {
        id = "${aws_launch_template.web.id}" 
        version = "$Latest"     
    }

    tag {
        key = "Name"
        value = "instance-ASG"
        propagate_at_launch = true
    }
}

resource "aws_autoscaling_policy" "autoscalingPolicy" {
    name = "Autoscaling-Policy"
    policy_type = "TargetTrackingScaling"
    autoscaling_group_name = "${aws_autoscaling_group.autoScalingGroup.name}"

    target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = 25.0
  }
}

/*
https://octopus.com/blog/dynamic-worker-army
https://davidwzhang.com/2017/04/04/use-terraform-to-set-up-aws-auto-scaling-group-with-elb/
*/

