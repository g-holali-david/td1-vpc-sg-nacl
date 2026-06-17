# Sous-reseau + table de routage (route 0.0.0.0/0 -> IGW)
resource "aws_subnet" "td" {
  vpc_id                  = data.aws_vpc.default.id
  cidr_block              = var.cidr
  availability_zone       = var.az
  map_public_ip_on_launch = true

  tags = {
    Name = "td-subnet-${var.owner}"
  }
}

resource "aws_route_table" "td" {
  vpc_id = data.aws_vpc.default.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = data.aws_internet_gateway.default.id
  }

  tags = {
    Name = "td-rt-${var.owner}"
  }
}

resource "aws_route_table_association" "td" {
  subnet_id      = aws_subnet.td.id
  route_table_id = aws_route_table.td.id
}
