# Damn Vulnerable DeFi: My solutions

These are my solutions to the challenge; you can find them in the corresponding test file :)!

You can find an explanation of the exploit itself in each test, within its dedicated comment section. Feel free to use any of this code for studying/teaching purposes.


## Install

1. Clone the repository.
2. Checkout the latest release (for example, `git checkout v4.1.0`)
3. Rename the `.env.sample` file to `.env` and add a valid RPC URL. This is only needed for the challenges that fork mainnet state.
4. Either install [Foundry](https://book.getfoundry.sh/getting-started/installation), or use the [provided devcontainer](./.devcontainer/) (In VSCode, open the repository as a devcontainer with the command "Devcontainer: Open Folder in Container...")
5. Run `forge build` to initialize the project.

## Usage

Each challenge is made up of:

- A prompt located in `src/<challenge-name>/README.md`.
- A set of contracts located in `src/<challenge-name>/`.
- A [Foundry test](https://book.getfoundry.sh/forge/tests) located in `test/<challenge-name>/<ChallengeName>.t.sol`.

All code, practices and patterns in this repository are DAMN VULNERABLE and for educational purposes only.

DO NOT USE IN PRODUCTION.
