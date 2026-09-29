# Verifying signatures

CI signs each image with cosign. The image installs `cosign.pub` as
`/etc/pki/containers/<image>.pub`, adds a `sigstoreSigned` policy for its
repository to the containers policy, and enables sigstore attachments in
`/etc/containers/registries.d/<image>.yaml`, where `<image>` is `bazzite-ovt`
or `fedora-cosmic-ovt`. Bazzite keeps its policy in
`/etc/containers/policy.json`, and Fedora 45 in
`/usr/share/containers/policy.json`.

A machine that has its own `/etc/containers/policy.json`, for example one
upgraded from Fedora 44 or edited by hand, reads only that file, so the
policy in the COSMIC image does not apply there. Check with
`grep fedora-cosmic-ovt /etc/containers/policy.json`. If the file exists and
the image is missing from it, copy the entry from
`/usr/share/containers/policy.json` or remove the local file.

The policy ships inside the image, so the first switch from the base image
cannot check the signature. Once the machine runs the image, every
`bootc upgrade` and `bootc switch` to its repository pulls through that
policy, and bootc refuses a build without a valid signature.

## Bazzite

Bazzite's policy has `reject` as its top-level default, so there you can also
pass `--enforce-container-sigpolicy`, which makes bootc check that the policy
requires signatures before it pulls.

```bash
sudo bootc switch --enforce-container-sigpolicy ghcr.io/goproslowyo/bazzite-ovt:latest
```

## Fedora COSMIC

Fedora's policy accepts anything by default, and
`--enforce-container-sigpolicy` refuses such a policy, so on the COSMIC image
use plain `bootc switch` and `bootc upgrade`. The repository entry still
applies to them.

The `ostree-image-signed:docker://` form is for `rpm-ostree rebase`.
`bootc switch` takes a plain image reference.

To sign a fork's images with your own key, see
[Building](building.md#signing-in-a-fork).
