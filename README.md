
## Description
A free tool designed to automate the package creation, maintenance, and delivery process on Windows. It currently supports creating Chocolatey packages from GitHub releases, but its design allows for future expansion, with plans to support more packaging formats and sources.

## Notes
- Originally, this project was intended for my personal use to automate the creation and updating of Chocolatey packages from GitHub-hosted project releases. Please note that when I began this project, I saw it as an opportunity to learn PowerShell. While the project is functional, I am aware that the code can be optimized and rewritten for enhanced clarity. I plan to do so after implementing the remaining major features.

- Chocolatey offers an official automatic package builder, which seems to take a similar approach, but it is only available with Chocolatey for Business, priced at $17/year per license with a minimum purchase of 100 licenses. I developed this project to provide similar functionality for individuals who appreciate automation but might not have $1,700 to burn for the sake of convenience.

## Features
### Completed Features
- **Package Creation**: Generates packages from GitHub repository links containing software installers and zips.
  - **Data Retrieval**: Automatically gathers package data (name, icon, description, release notes, version, etc.).
    - **Installer Data Extraction**: Identifies installer type and sets appropriate command line arguments.
    - **GitHub Repository Data**: Retrieves release notes and descriptions, if available.
    - **Icon Retrieval**: Sources icons from linked project sites as a fallback method.
- **Update Checks**: Uses GitHub Actions to periodically check and update packages for new releases.
  - **Release Identification**: Detects new software releases.
  - **Package Information Update**: Updates package details for new releases.
  - **New Package Creation**: Generates updated software packages.
- **Package Distribution**: Automatically uploads packages to GitHub Packages for convenient delivery.
- **Hosting Support**: Facilitates both local and remote (GitHub Packages) hosting.
- **File Selection**: Allows selection of specific files from releases for packaging.

### Future Enhancements (ToDo)
- **Additional Packaging Formats**: Plan to include support for various other packaging formats.
- **Broader Source Support**: Extend package creation capabilities to include non-GitHub sources.

## Setup Instructions
### Local Hosting
1. **Clone the Repository**: Download the repository to your local machine.
2. **Configure Chocolatey Source**: Add the path to the 'packages' folder in your cloned repository as a Chocolatey source (e.g., `E:\Documents\GitHub\CustomPackages\packages`).

### Remote Hosting
1. **Generate Personal Access Token**: Create a personal access token on GitHub with the required permissions.
2. **Setup Chocolatey Source**: Add the NuGet package URL to Chocolatey using your username (e.g., `https://nuget.pkg.github.com/<YourUsername>/index.json`).
   - Remember to include your GitHub username and personal access token when configuring the source.

## Usage Guidelines
1. **Link Selection**: Copy the direct link to the desired file in the release, or use the URL of the main GitHub repository page. 
   - *Note*: If you don't specify an asset, the program selects the first supported file type available in the release.
2. **Automatic Processing**: Once the link is provided, the program takes over. It automatically creates the package and will continue to check for updates periodically.

#### Example
- To package a release from `https://github.com/exampleuser/exampleproject`, simply input this URL. The program will identify the latest release, select the appropriate file, create the package, and monitor for future updates.
