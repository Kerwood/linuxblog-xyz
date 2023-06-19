---
title: Creating Kubernetes CRDs with Rust
date: 2023-06-19 19:43:09
author: Patrick Kerwood
excerpt: |
  You can extend Kubernetes with your own custom objects,
  but before you can do that you will need create a Custom Resource Definition so that Kubernetes knows what the
  object is allowed to look like. In this post I will create a very simple Kubernetes CRD for a Book kind using Rust and kube-rs.

type: post
blog: true
tags: [kubernetes, rust]
meta:
- name: description
  content: How to create a Custom Resource Definition using Rust
---
{{ $frontmatter.excerpt }}

Start by initiating a new Rust package.
```sh
cargo init book-crd
```

Add below dependencies to the `cargo.toml` file.
```toml
kube = { version = "0.83.0", features = ["runtime", "derive"] }
k8s-openapi = { version = "0.18.0", features = ["v1_26"] }
serde = "1.0.155"
serde_derive = "1.0.155"
serde_json = "1.0.94"
serde_yaml = "0.9.19"
schemars = "0.8.12"
```

Moving on to `main.rs`, add the nessacary libraries to the top of the file.
```rust
#[macro_use]
extern crate serde_derive;
use kube::{CustomResource, CustomResourceExt};
use schemars::JsonSchema;
```

Create a `BookSpec` struct with your desired properties. If you are reading this post you are probably already familiar
with Kubernetes, I will not go into details with the `kube` properties, they are pretty self-explanatory.

```rust
#[derive(CustomResource, Debug, Serialize, Deserialize, Default, Clone, JsonSchema)]
#[kube(group = "linuxblog.xyz", version = "v1", kind = "Book", namespaced)]
#[kube(status = "BookStatus")]
pub struct BookSpec {
    pub title: String,
    pub authors: Option<Vec<String>>,
    pub isbn: u16,
}
```

Adding a Status spec is optional.
```rust
#[derive(Deserialize, Serialize, Clone, Debug, Default, JsonSchema)]
pub struct BookStatus {
    pub is_ok: bool,
    pub is_synced: bool,
}
```

In the `main` function print out the `Book` CRD.
```rust
fn main() {
    println!("{}", serde_yaml::to_string(&Book::crd()).unwrap());
}
```

That is it. Do a `cargo run` and it will print out the Custom Resource Definition as YAML.

## References
- [Kube Derive Custom Resource](https://docs.rs/kube/latest/kube/derive.CustomResource.html)
---


