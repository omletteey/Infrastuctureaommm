# Terraform configuration is managed in backend.tf
# Provider configuration is managed in backend.tf

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = "autoscale-rg"
  location = "Southeast Asia"
}

# Virtual Network
resource "azurerm_virtual_network" "vnet" {
  name                = "main-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

# Subnets (3 subnets in different availability zones)
resource "azurerm_subnet" "public" {
  count                = 3
  name                 = "public-subnet-${count.index + 1}"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [cidrsubnet("10.0.0.0/16", 8, count.index + 1)]
}

# Associate Network Security Group to the first subnet (where VMSS is deployed)
resource "azurerm_subnet_network_security_group_association" "main" {
  subnet_id                 = azurerm_subnet.public[0].id
  network_security_group_id = azurerm_network_security_group.vm_sg.id
}

# Network Security Group for VM
resource "azurerm_network_security_group" "vm_sg" {
  name                = "vm-nsg"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  security_rule {
    name                       = "AllowHTTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowSSH"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Public IP for Load Balancer
resource "azurerm_public_ip" "lb_ip" {
  name                = "lb-public-ip"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Load Balancer
resource "azurerm_lb" "main" {
  name                = "public-lb"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "PublicLBFront"
    public_ip_address_id = azurerm_public_ip.lb_ip.id
  }
}

# Backend Address Pool
resource "azurerm_lb_backend_address_pool" "bpepool" {
  name = "backend-pool"
  #   resource_group_name = azurerm_resource_group.main.name
  loadbalancer_id = azurerm_lb.main.id
}

# Health Probe
resource "azurerm_lb_probe" "http_probe" {
  name = "http-probe"
  #   resource_group_name = azurerm_resource_group.main.name
  loadbalancer_id = azurerm_lb.main.id
  protocol        = "Http"
  port            = 80
  request_path    = "/"
}

# Load Balancer Rule
resource "azurerm_lb_rule" "http_rule" {
  name                           = "http-rule"
  loadbalancer_id                = azurerm_lb.main.id
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "PublicLBFront"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.bpepool.id]
  probe_id                       = azurerm_lb_probe.http_probe.id
}


# Availability Set
resource "azurerm_availability_set" "vm_as" {
  name                         = "vm-avset"
  location                     = azurerm_resource_group.main.location
  resource_group_name          = azurerm_resource_group.main.name
  platform_fault_domain_count  = 2
  platform_update_domain_count = 2
  managed                      = true
}

# Virtual Machine Scale Set
resource "azurerm_linux_virtual_machine_scale_set" "vmss" {
  name                = "nginx-vmss"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "Standard_B2s"
  instances           = 3
  admin_username      = "azureuser"
  
  admin_ssh_key {
    username   = "azureuser"
    public_key = file("adminterra.pub")
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  #   subnet_id                   = azurerm_subnet.public[0].id
  upgrade_mode                    = "Manual"
  overprovision                   = true
  disable_password_authentication = true

  network_interface {
    name    = "vmss-nic"
    primary = true

    ip_configuration {
      name                                   = "vmss-ipconfig"
      primary                                = true
      subnet_id                              = azurerm_subnet.public[0].id
      load_balancer_backend_address_pool_ids = [azurerm_lb_backend_address_pool.bpepool.id]
    }
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 30
  }

  custom_data = base64encode(<<-EOF
              #!/bin/bash
              echo "Provision started at $(date)" >> /var/log/provision.log
              apt-get update -y
              apt-get install nginx -y
              
              # Create a custom index page to verify load balancer is working
              echo "<h1>Hello from Azure VM Scale Set!</h1>" > /var/www/html/index.html
              echo "<p>Server: $(hostname)</p>" >> /var/www/html/index.html
              echo "<p>Timestamp: $(date)</p>" >> /var/www/html/index.html
              
              systemctl enable nginx
              systemctl start nginx
              
              # Install Docker
              curl -fsSL https://get.docker.com -o get-docker.sh
              sh get-docker.sh
              usermod -aG docker azureuser
              apt-get install docker-compose-plugin -y
              
              echo "Provision finished at $(date)" >> /var/log/provision.log
            EOF
  )
}

# Auto-scaling Rules
resource "azurerm_monitor_autoscale_setting" "vmss_scale" {
  name                = "vmss-autoscale"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  target_resource_id  = azurerm_linux_virtual_machine_scale_set.vmss.id

  profile {
    name = "default"

    capacity {
      minimum = "3"
      maximum = "5"
      default = "3"
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.vmss.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 60
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.vmss.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 30
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }
  }

  # notification {
  #   email {
  #     send_to_subscription_administrator    = true
  #     send_to_subscription_co_administrator = true
  #   }
  # }
  
  
}

# Output the Load Balancer Public IP
output "load_balancer_public_ip" {
  description = "Public IP address of the Load Balancer"
  value       = azurerm_public_ip.lb_ip.ip_address
}

output "load_balancer_fqdn" {
  description = "FQDN of the Load Balancer"
  value       = azurerm_public_ip.lb_ip.fqdn
}
