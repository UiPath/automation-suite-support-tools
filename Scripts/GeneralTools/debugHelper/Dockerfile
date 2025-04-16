FROM registry.uipath.com/uipath/sf-k8-utils-rhel:2025.04.02

# Set environment variable to avoid interactive prompts
ENV ACCEPT_EULA=Y

# Install AWS CLI
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && \
    unzip awscliv2.zip && \
    ./aws/install && \
    rm -rf aws awscliv2.zip

# Install Azure CLI
RUN yum install -y azure-cli && \
    yum clean all
