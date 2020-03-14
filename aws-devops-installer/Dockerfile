FROM centos:7

# Install unzip, git, aws and terraform.
RUN yum install -y unzip-6.0-20.el7.x86_64;
RUN yum-config-manager --add-repo http://opensource.wandisco.com/centos/7/git/x86_64/;  \
    yum-config-manager --save --setopt=opensource.wandisco.com_centos_7_git_x86_64_.gpgkey=http://opensource.wandisco.com/RPM-GPG-KEY-WANdisco;  \
    yum install -y git-2.18.0-1.WANdisco.402.x86_64;
RUN mkdir -p /tmp/aws-devops/;  \
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/aws-devops/awscliv2.zip";  \
    unzip -qq /tmp/aws-devops/awscliv2.zip -d /root/;  \
    rm -rf /tmp/aws-devops/;  \
    /root/aws/install;
RUN mkdir -p /tmp/aws-devops/;  \
    curl "https://releases.hashicorp.com/terraform/0.12.20/terraform_0.12.20_linux_amd64.zip" -o "/tmp/aws-devops/terraform.zip";  \
    unzip -qq /tmp/aws-devops/terraform.zip -d /tmp/aws-devops/;  \
    cp /tmp/aws-devops/terraform /usr/local/bin/terraform;  \
    rm -rf /tmp/aws-devops/;

# Copy the entrypoint, install and uninstall scripts.
COPY "." "/"
RUN \
    chmod +x "/entrypoint.sh";  \
    chmod +x "/install.sh";  \
    chmod +x "/uninstall.sh";

ENTRYPOINT ["/entrypoint.sh"]