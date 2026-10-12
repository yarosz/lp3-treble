#!/usr/bin/env python3
# Runs INSIDE the Alpine container. Do not call directly; use scripts/patch-gsi.sh.
# Removes a GSI's AVB hashtree footer before patching and adds an equivalent one after.
#
#   avb-footer.py save    <avbtool.py> <image> <state.json>   read the footer, then erase it
#   avb-footer.py restore <avbtool.py> <image> <state.json>   add a fresh hashtree footer
#
# The fresh footer keeps the partition name, hash algorithm, block size, salt, rollback index,
# header flags and properties. It has no FEC and no signature (algorithm NONE), which DSU accepts on
# an unlocked bootloader. Anything else in the vbmeta (hash or chain descriptors, kernel cmdlines,
# hashtree flags) is refused rather than dropped.
import importlib.util
import json
import os
import subprocess
import sys
import tempfile


def die(msg):
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(1)


def load_avbtool(path):
    spec = importlib.util.spec_from_file_location("avbtool", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def parse(avb, image):
    try:
        footer, header, descriptors, _ = avb.Avb()._parse_image(avb.ImageHandler(image, read_only=True))
    except avb.AvbError as e:
        die(f"cannot parse AVB metadata of {image}: {e}")
    if footer is None:
        die(f"{image} has no AVB footer")
    return footer, header, descriptors


def save(avbtool, image, state):
    avb = load_avbtool(avbtool)
    footer, header, descriptors = parse(avb, image)
    trees, props, other = [], [], []
    for d in descriptors:
        if isinstance(d, avb.AvbHashtreeDescriptor):
            trees.append(d)
        elif isinstance(d, avb.AvbPropertyDescriptor):
            props.append(d)
        else:
            other.append(type(d).__name__)
    if other:
        die(f"unsupported AVB descriptors {sorted(set(other))}; only one hashtree descriptor plus properties is handled")
    if len(trees) != 1:
        die(f"expected exactly one hashtree descriptor, found {len(trees)}")
    t = trees[0]
    if t.data_block_size != t.hash_block_size:
        die(f"data block size {t.data_block_size} != hash block size {t.hash_block_size}")
    if t.flags != 0:
        die(f"hashtree descriptor flags {t.flags} are not supported")
    if t.image_size != footer.original_image_size:
        die(f"hashtree covers {t.image_size} bytes but the original image is {footer.original_image_size}")
    out_props = []
    for p in props:
        try:
            out_props.append([p.key, p.value.decode("utf-8")])
        except UnicodeDecodeError:
            die(f"property {p.key} has a non-UTF-8 value")
        if ":" in p.key:
            die(f"property key {p.key!r} contains ':'")
    s = {
        "partition_name": t.partition_name,
        "hash_algorithm": t.hash_algorithm,
        "block_size": t.data_block_size,
        "salt": t.salt.hex(),
        "rollback_index": header.rollback_index,
        "rollback_index_location": header.rollback_index_location,
        "flags": header.flags,
        "props": out_props,
        "original_image_size": footer.original_image_size,
        "root_digest": t.root_digest.hex(),
        "fec_num_roots": t.fec_num_roots,
    }
    with open(state, "w") as f:
        json.dump(s, f, indent=1)
    print(f"avb: footer found: partition {s['partition_name']}, {s['hash_algorithm']}, block {s['block_size']}, "
          f"fec roots {s['fec_num_roots']}, rollback index {s['rollback_index']}, {len(out_props)} prop(s), "
          f"fs {s['original_image_size']} bytes, root digest {s['root_digest']}")
    subprocess.run([sys.executable, avbtool, "erase_footer", "--image", image], check=True)
    print("avb: footer erased")


def restore(avbtool, image, state):
    with open(state) as f:
        s = json.load(f)
    cmd = [sys.executable, avbtool, "add_hashtree_footer", "--image", image,
           "--partition_name", s["partition_name"], "--hash_algorithm", s["hash_algorithm"],
           "--block_size", str(s["block_size"]), "--salt", s["salt"],
           "--rollback_index", str(s["rollback_index"]),
           "--rollback_index_location", str(s["rollback_index_location"]),
           "--flags", str(s["flags"]), "--algorithm", "NONE", "--do_not_generate_fec"]
    for k, v in s["props"]:
        cmd += ["--prop", f"{k}:{v}"]
    subprocess.run(cmd, check=True)

    avb = load_avbtool(avbtool)
    footer, header, descriptors = parse(avb, image)
    t = [d for d in descriptors if isinstance(d, avb.AvbHashtreeDescriptor)]
    got_props = [[d.key, d.value.decode("utf-8")] for d in descriptors if isinstance(d, avb.AvbPropertyDescriptor)]
    if len(t) != 1:
        die("new footer: expected one hashtree descriptor")
    t = t[0]
    checks = [
        ("partition name", t.partition_name, s["partition_name"]),
        ("hash algorithm", t.hash_algorithm, s["hash_algorithm"]),
        ("salt", t.salt.hex(), s["salt"]),
        ("rollback index", header.rollback_index, s["rollback_index"]),
        ("rollback index location", header.rollback_index_location, s["rollback_index_location"]),
        ("flags", header.flags, s["flags"]),
        ("props", got_props, s["props"]),
        ("fec roots", t.fec_num_roots, 0),
        ("covered size", t.image_size, footer.original_image_size),
    ]
    for name, got, want in checks:
        if got != want:
            die(f"new footer: {name} is {got!r}, want {want!r}")
    # verify_image recomputes the hashtree over the data and compares the root digest. It reads the data
    # from "<partition name>.img" next to the image it is given, so point it at a symlink with that name.
    with tempfile.TemporaryDirectory() as d:
        link = os.path.join(d, s["partition_name"] + ".img")
        os.symlink(os.path.abspath(image), link)
        subprocess.run([sys.executable, avbtool, "verify_image", "--image", link], check=True,
                       stdout=subprocess.DEVNULL)
    print(f"avb: new hashtree footer: fs {footer.original_image_size} bytes, image {footer_image_size(image)} bytes, "
          f"no FEC, algorithm NONE, root digest {t.root_digest.hex()} (verify_image ok)")


def footer_image_size(image):
    with open(image, "rb") as f:
        f.seek(0, 2)
        return f.tell()


def main():
    if len(sys.argv) != 5 or sys.argv[1] not in ("save", "restore"):
        die("usage: avb-footer.py save|restore <avbtool.py> <image> <state.json>")
    (save if sys.argv[1] == "save" else restore)(*sys.argv[2:])


if __name__ == "__main__":
    main()
