# Copyright 2022 Shantanoo 'Shan' Desai <sdes.softdev@gmail.com>

#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at

#       http://www.apache.org/licenses/LICENSE-2.0

#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#  limitations under the License.


## Variable will be set via the Command line defined under the `vars` directory
variable "ubuntu_version" {
    type = string
}

variable "ubuntu_iso_file" {
    type = string
}

variable "vm_template_name" {
    type = string
    default = "ckoctrl"
}

locals {
    vm_name = "${var.vm_template_name}-${var.ubuntu_version}"
    output_dir = "output/${local.vm_name}"
}

source "qemu" "custom_image" {
    vm_name     = "${local.vm_name}"
    
    iso_url      = "../iso/ubuntu-22.04.1-live-server-amd64.iso"
    iso_checksum = "sha256:10f19c5b2b8d6db711582e0e27f5116296c34fe4b313ba45f9b201a5007056cb"
   #ub2004 iso_checksum = "sha256:5035be37a7e9abbdc09f0d257f3e33416c1a0fb322ba860d42d74aa75c3468d4"

    # Location of Cloud-Init / Autoinstall Configuration files
    # Will be served via an HTTP Server from Packer
    http_directory = "http"

    # Boot Commands when Loading the ISO file with OVMF.fd file (Tianocore) / GrubV2
    boot_command = [
        "<spacebar><wait><spacebar><wait><spacebar><wait><spacebar><wait><spacebar><wait>",
        "e<wait>",
        "<down><down><down><end>",
        " autoinstall ds=nocloud-net\\;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/",
        "<f10>"
    ]
    
    boot_wait = "5s"

    # QEMU specific configuration
    cpus             = 4
    memory           = 4096
    accelerator      = "kvm" # use none here if not using KVM
    disk_size        = "30G"
    disk_compression = true

    # Use the UEFI Bootloader OVMF file on the Build Machine
    qemuargs         = [
        ["-bios", "/usr/share/OVMF/OVMF_CODE.fd"]
    ]

    # Final Image will be available in `output/packerubuntu-*/`
    output_directory = "${local.output_dir}"

    # SSH configuration so that Packer can log into the Image
    ssh_password    = "123456789"
    ssh_username    = "admin"
    ssh_timeout     = "660m"
    shutdown_command = "sleep 5m; echo 'ckoctrl sleeping before shutdown' | sudo -S shutdown -P now"
    headless        = true # NOTE: set this to true when using in CI Pipelines
}

build {
    name    = "custom_build"
    sources = [ "source.qemu.custom_image" ]

    provisioner "file" {
      source = "scripts/"
      destination = "/tmp/"
    }

    provisioner "file" {
     source = "prepImgChart/cko_resources/"
     destination = "/tmp/resources"
    }

    # Wait till Cloud-Init has finished setting up the image on first-boot
    provisioner "shell" {
    execute_command = "echo '123456789' | sudo -S bash -c '{{ .Vars }} {{ .Path }}'"
    expect_disconnect = true
    valid_exit_codes = [0, 2300218]
    environment_vars = [
      "http_proxy=http://proxy.esl.cisco.com:80",
      "https_proxy=http://proxy.esl.cisco.com:80",
      "no_proxy=localhost,127.0.0.1,172.28.184.8,172.28.184.14,172.28.184.18,172.28.184.140,10.30.120.20,172.28.184.12,172.28.184.145,172.28.184.146,172.28.184.147,172.28.184.148,172.28.184.149,fab14-compute-1.noiro.lab,fab14-compute-2.noiro.lab,fab14-compute-3.noiro.lab,fab14-compute-4.noiro.lab,fab14-compute-5.noiro.lab,fab14-compute-1,fab14-compute-2,fab14-compute-3,fab14-compute-4,fab14-compute-5,1.100.101.11,1.100.101.12,1.100.101.13,1.100.101.14,1.100.101.15,172.28.184.12,engci-jenkins-sjc.cisco.com,10.96.0.0/12,10.2.80.1/21",
      "DEBIAN_FRONTEND=noninteractive",
    ]
        inline = [
            "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do echo 'Waiting for Cloud-Init...'; sleep 1; done" ,
            "echo sumit-printenv",
            "printenv",
            "wget google.com",
            "/tmp/0_initial_install.sh",
        ]
    }


    # Finally Generate a Checksum (SHA256) which can be used for further stages in the `output` directory
    post-processor "checksum" {
        checksum_types      = [ "sha256" ]
        output              = "${local.output_dir}/${local.vm_name}.{{.ChecksumType}}"
        keep_input_artifact = true
    }
}
