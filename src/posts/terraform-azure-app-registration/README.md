---
title: Creating Azure App Registrations with Terraform
date: 2022-07-26 20:16:02
author: Patrick Kerwood
excerpt: In this blog post I will introduce a Terraform script I have created for managing Azure App Registrations. The code supports two different kinds of App Registrations, one for user logins with groups assignments and one for services which includes adding App Roles and API Permissions.
type: post
blog: true
tags: [terraform, azure]
meta:
  - name: description
    content: Creating Azure App Registrations with Terraform.
---

{{ $frontmatter.excerpt }}

You can find the Terraform files needed at this repository, <https://github.com/Kerwood/azure-app-registration-terraform>.

The folder structure is as shown below.

```
.
├── main.tf
└── modules
    ├── app-registration-api
    ├── app-registration-spa
    ├── grant-admin-consent
    └── group-assignment
```

The root contains a `main.tf` file with examples. The `modules` folder contains four modules and are used for creating the resources needed and are as follows.

- The `app-registration-api` module will create the service-to-service App Registration and supports App Roles and API Permissions.
- The `app-registration-spa` module will create the App Registrations for user logins and supports group assignments.
- The `grant-admin-consent` module will grant admin consent on all API Permissions specified in the `app-registration-api` module.
- The `group-assignment` module will assign the specified groups in the `app-registration-spa` module to the Enterprise Application.


At the top of the `main.tf` file you will find below configuration. Configure it to fit your needs, at the very least, add your Azure Tenant ID to the `azuread` provider.

```
terraform {
  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.26.1"
    }
  }

  backend "local" {}
}

provider "azuread" {
  tenant_id = "<your-tenant-id-here>"
}
```

Lets create some App Registrations. The `main.tf` file contains some examles, so lets use them.

## User login example

Below example creates an App Registration for user logins, using the "Single-page application" platform. It adds two redirect URI's and assigns two security
groups to the Enterprise Application. The MS Graph permission `User.Read` will be added as an API permission and will be granted admin consent.

It also creates an "optional groups claim", that add the names of the groups assigned to the application, (if the user is a member of them) to the ID and Access token.

```
module "my_app_reg_module_name_01" {
  source           = "./modules/app-registration-spa"
  display_name     = "my-app-reg-display-name"

  redirect_uris = [
    "http://localhost:4200/usersignin",
    "https://example.org/usersignin"
  ]

  group_assignments = [
    "MyGroup_Admin",
    "MyGroup_User"
  ]
}
```

## Service login example

Below example creates an App Registration for a service with two custom App Roles, no API permissions are set. Since it's a requirement to have atleast one API
permissions, the MS Graph `User.Read` permissions is set in the module, but is not granted admin consent, nor does it need to.

```
module "my_app_reg_module_name_02" {
  source       = "./modules/app-registration-api"
  display_name = "my-app-reg-display-name"

  app_roles    = [
    {
      display_name = "MyService Read"
      value        = "MyService.Read"
      description  = "This is a description of what my role does."
    },
    {
      display_name = "MyService Write"
      value        = "MyService.Write"
      description  = "This is a description of what my role does."
    }
  ]

  api_permissions = []
}
```

Below example creates another service App Registration, but this time no App Roles are created. Instead two API permissions are set.

The first permission refers to the application ID from the example above, same goes for the App Role ID's.
It's possible that you want to give API permissions from another App Registration that is not part of your Terraform script. No worries, just add the ID's of the application and App Roles. 
You can get the ID's with the `az ad sp list --display-name <app-reg-name> -o yaml ` command.


```
module "my_app_reg_module_name_03" {
  source           = "./modules/app-registration-api"
  display_name     = "my-app-reg-display-name"

  app_roles        = []

  api_permissions = [
    {
      application_id = module.my_app_reg_module_name_02.application_id
      role_ids     = [
        module.my_app_reg_module_name_02.app_role_ids["MyService.Read"],
        module.my_app_reg_module_name_02.app_role_ids["MyService.Write"]
      ]
    },
    {
      application_id = "00000000-0000-0000-0000-000000000000"
      role_ids     = [
        "00000000-0000-0000-0000-000000000000",
        "00000000-0000-0000-0000-000000000000"
      ]
    },
  ]
}
```

## Terraform Output

Each module outputs information about the resource. Below is an example that will output information about all three examles we have created in this blog post.

```
output "app_registrations" {
  value = { app_registrations = [
    {
      display_name      = module.my_app_reg_module_name_01.display_name
      application_id    = module.my_app_reg_module_name_01.application_id
      roles             = module.my_app_reg_module_name_01.app_role_ids
      group_assignments = module.my_app_reg_module_name_01.group_assignments
      redirect_uris     = module.my_app_reg_module_name_01.redirect_uris
    },
    {
      display_name    = module.my_app_reg_module_name_02.display_name
      application_id  = module.my_app_reg_module_name_02.application_id
      roles           = module.my_app_reg_module_name_02.app_role_ids
      api_permissions = module.my_app_reg_module_name_02.api_permissions
    },
    {
      display_name    = module.my_app_reg_module_name_03.display_name
      application_id  = module.my_app_reg_module_name_03.application_id
      roles           = module.my_app_reg_module_name_03.app_role_ids
      api_permissions = module.my_app_reg_module_name_03.api_permissions
    }
  ]}
}
``` 

You can output the details using the below command.

```sh
terraform output app_registrations
```

If you want to pipe the details to another application you can output it as JSON or pipe it through `yq` to get YAML.

```sh
terraform output -json app_registrations | yq -P
```

This will output below example.

```yaml
app_registrations:
  - application_id: ae63b0e6-0dbe-11ed-861d-0242ac120002
    display_name: my-app-reg-display-name-01
    group_assignments:
      - MyGroup_Admin
      - MyGroup_User
    redirect_uris:
      - http://localhost:4200/usersignin
      - https://example.org/usersignin
    roles: {}

  - api_permissions: []
    application_id: b4bab250-0dbe-11ed-861d-0242ac120002
    display_name: my-app-reg-display-name-02
    roles:
      MyService.Read: bb3fa2a2-0dbe-11ed-861d-0242ac120002
      MyService.Write: c3d3eb76-0dbe-11ed-861d-0242ac120002

  - api_permissions:
      - application_id: b4bab250-0dbe-11ed-861d-0242ac120002
        role_ids:
          - bb3fa2a2-0dbe-11ed-861d-0242ac120002
          - c3d3eb76-0dbe-11ed-861d-0242ac120002
    application_id: cbdd7bca-0dbe-11ed-861d-0242ac120002
    display_name: my-app-reg-display-name-03
    roles: {}

```