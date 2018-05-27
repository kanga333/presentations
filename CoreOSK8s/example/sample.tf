module "bare-metal-mercury" {
  source = "git::https://github.com/poseidon/typhoon//bare-metal/container-linux/kubernetes?ref=v1.10.1"

  # bare-metal
  cluster_name            = "mercury"
  matchbox_http_endpoint  = "http://matchbox.example.com"
  container_linux_channel = "stable"
  container_linux_version = "1632.3.0"

  # configuration
  k8s_domain_name    = "node1.example.com"
  ssh_authorized_key = "ssh-rsa AAAAB3Nz..."
  asset_dir          = "/home/user/.secrets/clusters/mercury"

  # machines
  controller_names   = ["node1"]
  controller_macs    = ["52:54:00:a1:9c:ae"]
  controller_domains = ["node1.example.com"]
  worker_names       = ["node2"]
  worker_macs        = ["52:54:00:b2:2f:86"]
  worker_domains     = ["node2.example.com"]
}
