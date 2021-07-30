#!/bin/bash
sudo apt update -y
sudo apt install nginx -y
sudo curl http://169.254.169.254/latest/meta-data/hostname | sudo tee /var/www/html/index.nginx-debian.html
sudo service nginx start