# Setup DigitalOcean Provider - use this section for provider related configuration
# for more details visit: https://www.terraform.io/docs/providers/do/index.html

provider "digitalocean" {
  token = "${var.do_token}"
}
