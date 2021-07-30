resource "aws_vpc" "main" {
    cidr_block = "10.0.0.0/16"

    tags = {
        Name = "Project_ELB"
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

resource "aws_subnet" "Pub_Network1" {
    vpc_id = "${aws_vpc.main.id}"
    cidr_block = "10.0.0.0/24"
    availability_zone = "eu-west-3a"
    map_public_ip_on_launch = true

    tags = {
        Name = "Public1"
    }
}


resource "aws_subnet" "Pub_Network2" {
    vpc_id = "${aws_vpc.main.id}"
    cidr_block = "10.0.1.0/24"
    availability_zone = "eu-west-3b"
    map_public_ip_on_launch = true

    tags = {
        Name = "Public2"
    }
}


resource "aws_route_table_association" "Public_route1" {
    subnet_id = "${aws_subnet.Pub_Network1.id}"
    route_table_id = "${aws_route_table.Internet_Gateway.id}"
}


resource "aws_route_table_association" "Public_route2" {
    subnet_id = "${aws_subnet.Pub_Network2.id}"
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
##    vpc_security_group_ids = ["${aws_security_group.SG_WEB.id}"]

 /* placement {
    availability_zone = "eu-west-3a"
  }
*/

    monitoring {
      enabled = true
    }

    user_data = filebase64("./myscript.sh")
}

resource "aws_instance" "EC2_WEB" {
    vpc_security_group_ids = ["${aws_security_group.SG_WEB.id}"]
    subnet_id   = "${aws_subnet.Pub_Network1.id}"
    
    launch_template {
        id = "${aws_launch_template.web.id}" 
        version = "$Latest"     
    }

    tags = {
      Name = "Server_Web1"
    }
}


resource "aws_instance" "EC2_WEB2" {
    vpc_security_group_ids = ["${aws_security_group.SG_WEB.id}"]
    subnet_id   = "${aws_subnet.Pub_Network2.id}"

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
        "${aws_subnet.Pub_Network1.id}",
        "${aws_subnet.Pub_Network2.id}",
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
    min_size = 1
    desired_capacity = 2
    max_size = 4
    health_check_type = "ELB"
    load_balancers = "${aws_lb.Loadbalancer.id}"
    
    vpc_zone_identifier = [
        aws_subnet.Pub_Network1.id,
        aws_subnet.Pub_Network2.id
    ]

    launch_template {
        id = "${aws_launch_template.web.id}" 
        version = "$Latest"     
    }

}

resource "aws_autoscaling_attachment" "asg_attachment_bar" {
  autoscaling_group_name = aws_autoscaling_group.autoScalingGroup.id
  elb                    = aws_lb.Loadbalancer.id
}

/*
https://github.com/hashicorp/terraform-provider-aws/issues/6948

https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_group
https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_attachment
*/
