Project for creating infrastructure on AWS,
optionally, build local infrastructure Kubernetes cluster via Vagrant platform

1. K8s cluster
    Main Vagrant config file with additional configuration shell files
   Local infrastructure deployment

Files tf (Terraform)
   Deployment infrastructure on AWS, include VPC, RDS, CI/CD stages
   Theoretical template YAML file with Streamer application

2. Private registry
    Run container on local machine by following command
   "docker run -d -p 5000:5000 --restart=always --name registry -v docker:/var/lib/registry registry:2"
   there is a problem with http secure, 
   stage doesn't want push to private image, I know, how solve, I try launch this procedure in technologies
    Private registry YAML file attached.
   
3. CI/CD
    Jenkinsfile with all stages
   Jenkins deployment YAML file into cluster;
   Also, Jenkins config file from helm
   
4. Bonus
   The bonus itself is attached, above (files tf)
   

CodePipeline: there is no quick solution to deploy in EKS;
Jenkins: there is a problem with identifying certificate of EKS Cluster
