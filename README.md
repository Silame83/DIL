Project for creating infrastructure on AWS,
optionally, build local infrastructure Kubernetes cluster via Vagrant platform

1. K8s cluster
    Main Vagrant config file with additional configuration shell files
   Local infrastructure deployment
   ---------------------------------------------------------------------------
    Files tf (Terraform)
   Deployment infrastructure on AWS, include VPC, RDS, CI/CD stages
   
2. Private registry
    Run container on local machine by following command
   "docker run -d -p 5000:5000 --restart=always --name registry -v docker:/var/lib/registry registry:2"
   there is a problem with http secure, 
   stage doesn't want push to private image, I know, how solve, I try launch this procedure in technologies

3. CI/CD
    This stage works into Amazon Web Services (CodeBuild, CodePipeline)
   
4. Bonus
   The bonus itself is attached, above (files tf)
   
P.S. Difficulties that I still solve, integration with EKS via Jenkins or CodePipeline
CodePipeline: there is no quick solution to deploy in EKS;
Jenkins: there is a problem with identifying certificate of EKS Cluster