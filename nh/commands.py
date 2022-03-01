import json
import platform
import subprocess
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from functools import partial
from pathlib import Path

import click
import dateparser
from diskcache import Cache
from pyfzf.pyfzf import FzfPrompt
from xdg import xdg_cache_home

from nh import __version__, deps
from nh.utils import NixFile, SearchResult, cmd_print, find_gcroots, find_nixfiles


@click.group()
@click.version_option(__version__)
def cli() -> None:
    pass


@cli.command()
@click.argument(
    "path",
    type=click.Path(exists=True),
    envvar="FLAKE",
)
def repl(path):
    """
    Load a flake into a nix repl

    PATH to any nix file or container folder. If nothing is passed, the environment variable $FLAKE will be used
    """

    repl_flake = Path(__file__).parent / "repl-flake.nix"

    my_nixfile = NixFile(path)

    if my_nixfile.is_flake:
        subprocess.run(["nix", "flake", "show", str(my_nixfile.path)])
        subprocess.run(
            [
                "nix",
                "repl",
                "--arg",
                "flakepath",
                str(my_nixfile.path),
                str(repl_flake),
            ]
        )
    else:
        print(f"You are trying to load ${my_nixfile.path}, which is not a flake")


@cli.command()
@click.option(
    "-R",
    "--recursive",
    is_flag=True,
    help="If path is a directory, recurse through it.",
)
@click.argument("path", type=click.Path(exists=True), envvar="FLAKE")
@click.option("-n", "--dry-run", is_flag=True, help="Print commands and exit")
def update(path, recursive, dry_run):
    """
    Update a flake or any nix file containing fetchFromGitHub

    PATH to any nix file or container folder. If nothing is passed, the environment variable $FLAKE will be used
    """

    my_path = Path(path).resolve()

    if recursive and my_path.is_dir():
        my_nixfiles = find_nixfiles(my_path)
    else:
        my_nixfiles = [NixFile(my_path)]

    for nf in my_nixfiles:
        if nf.is_flake:
            cmd = ["nix", "flake", "update", str(nf)]
            cmd_print(cmd)
            if not dry_run:
                subprocess.run(cmd)

        elif nf.has_fetchFromGitHub:
            cmd = [deps.UNF, str(nf.path)]
            cmd_print(cmd)
            if not dry_run:
                subprocess.run(cmd)


@cli.command(
    name="switch",
    context_settings=dict(
        ignore_unknown_options=True,
        allow_extra_args=True,
    ),
)
@click.option("-n", "--dry-run", is_flag=True, help="Print commands and exit.")
@click.argument("flake", type=click.Path(exists=True), envvar="FLAKE", required=False)
@click.pass_context
def nixos_rebuild_switch(ctx, flake, dry_run):
    """
    Like 'nixos-rebuild switch', but with a diff with added/removed/changed packages.

    FLAKE: path to the flake to use. Will use environment variable $FLAKE, if nothing is passed.

    Extra options will be forwarded to nixos-rebuild.
    """
    nixos_rebuild(ctx)


@cli.command(
    name="boot",
    context_settings=dict(
        ignore_unknown_options=True,
        allow_extra_args=True,
    ),
)
@click.argument("flake", type=click.Path(exists=True), envvar="FLAKE", required=False)
@click.option("-n", "--dry-run", is_flag=True, help="Print commands and exit.")
@click.pass_context
def nixos_rebuild_boot(ctx, flake, dry_run):
    """
    Like 'nixos-rebuild boot', but with a diff with added/removed/changed packages.

    FLAKE: path to the flake to use. Will use environment variable $FLAKE, if nothing is passed.

    Extra options will be forwarded to nixos-rebuild.
    """
    nixos_rebuild(ctx)


@cli.command(
    name="test",
    context_settings=dict(
        ignore_unknown_options=True,
        allow_extra_args=True,
    ),
)
@click.argument(
    "flake", type=click.Path(exists=True, dir_okay=True), envvar="FLAKE", required=False
)
@click.option("-n", "--dry-run", is_flag=True, help="Print commands and exit.")
@click.pass_context
def nixos_rebuild_test(ctx, flake, dry_run):
    """
    Like 'nixos-rebuild test', but with a diff with added/removed/changed packages.

    FLAKE: path to the flake to use. Will use environment variable $FLAKE, if nothing is passed.

    Extra options will be forwarded to nixos-rebuild.
    """
    nixos_rebuild(ctx)


def nixos_rebuild(ctx: click.core.Context):
    my_flake = NixFile(Path(ctx.params["flake"]))
    cmd = [
        "sudo",
        "nixos-rebuild",
        ctx.command.name,
        "--flake",
        str(my_flake) + f"#{platform.node()}",
    ]
    if ctx.args:
        cmd.append(" ".join(ctx.args))

    cmd_print(cmd)

    profile_prev = Path("/run/current-system").resolve()

    if not ctx.params["dry_run"]:
        subprocess.run(cmd)
        profile_new = Path("/run/current-system").resolve()
        cmd_nvd = [deps.NVD, "diff", str(profile_prev), str(profile_new)]
        subprocess.run(cmd_nvd)


@click.option(
    "--flake",
    type=str,
    default="nixpkgs",
    show_default=True,
    required=False,
    help="""Flake to search in.""",
)
@click.option(
    "--max-results",
    type=int,
    default=10,
    show_default=True,
    required=False,
    help="""Maximum number of results with non-interactive search.
    May impact performance""",
)
@click.argument("query", type=str, default=None, required=False)
@cli.command()
def search(flake, query, max_results):
    """
    Super fast search for packages (optionally interactive)

    QUERY can be left empty to get a interactive search with fzf.
    """
    fzf = FzfPrompt(deps.FZF)

    try:
        search_cache = Cache(directory=str(xdg_cache_home() / "nix-nh"))
        pkgs = search_cache.get(f"pkgs-{flake}")
        assert pkgs
    except AssertionError:
        pkgs_json = json.loads(
            subprocess.check_output(["nix", "search", "--json", flake]).decode()
        )
        pkgs = set()
        for p in pkgs_json:
            pkgs.add(f"{pkgs_json[p]['pname']}")
        # Free memory maybe?
        del pkgs_json
        search_cache.set(f"pkgs-{flake}", pkgs, expire=259200)

    fzf_options = "--height=20%"
    if query:
        fzf_options += f" --filter='{query}'"
    responses = fzf.prompt(pkgs, fzf_options=fzf_options)

    responses = responses[:max_results]
    responses.reverse()

    with ThreadPoolExecutor() as executor:
        results = executor.map(partial(SearchResult, flake=flake), responses)

    for r in results:
        print()
        r.print()

    print()


@cli.command(name="gcr-clean")
@click.option(
    "--age",
    type=str,
    default="",
    show_default=True,
    required=False,
    help="""Any gcroot created at a time older will be selected for removal.
            Accepts human readable values (e.g. '7 days ago').""",
)
@click.option("-n", "--dry-run", is_flag=True, help="Don't actually remove anything.")
@click.option(
    "--root",
    type=click.Path(exists=True, dir_okay=True),
    default=Path.home(),
    required=False,
    help="Root directory to scan from.",
)
def gcr_clean(age, dry_run, root):
    """
    Find gcroots from a root directory, and delete them.
    A garbage collect root is a symlink from the store into a normal folder,
    and registered for gcroots, such that the dependencies of it won't be cleaned
    until you remove it (e.g build artifacts).
    """
    roots = find_gcroots(root)

    if age:
        max_age = dateparser.parse(age)
    else:
        max_age = datetime.now()

    for r in roots:
        if r.registration_time < max_age:
            print(f"Removing {r.destination}")
            if not dry_run:
                r.remove()
