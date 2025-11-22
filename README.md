# Git Commit Auto (with Gemini AI)

This script, `git-commit-auto`, automatically generates a conventional commit message for your staged changes using the Gemini AI and then executes the commit.

This allows you to run `git commit-auto` instead of `git commit -m "..."`.

![compare](https://github.com/user-attachments/assets/242b556f-5774-49c2-a482-e4ac707f8b2b)



## Dependencies


You must have the following command-line tools installed:


- `git`

- `curl` (for making API requests)

- `jq` (for parsing the API response)

You can typically install `curl` and `jq` using your system's package manager (like `apt`, `yum`, `brew`, or `pacman`).


## Setup Instructions

1. **Get a Gemini API Key:**

   - Go to Google AI Studio (or Google Cloud Console) and create an API key.

2. **Set Environment Variable:**

   - You need to securely store this API key as an environment variable named `GEMINI_API_KEY`.

   - Add the following line at the end to your shell's configuration file: nano (e.g., `~/.bashrc`, `~/.zshrc`, or `~/.profile`):

     ```
     export GEMINI_API_KEY="YOUR_API_KEY_HERE"
     ```

   - Replace `YOUR_API_KEY_HERE` with your actual key.

   - Reload your shell for the change to take effect (e.g., by running `source ~/.bashrc` or just opening a new terminal).

3. **Install the Script:**

   - Save the `git-commit-auto.sh` script from the previous file.

   - Rename it to just `git-commit-auto` (no `.sh` extension).

   - Make it executable:

     ```
     chmod +x git-commit-auto
     ```

   - Move it to a directory that is in your system's `PATH`. A common place is `/usr/local/bin`:

     ```
     sudo mv git-commit-auto /usr/local/bin/
     ```

     (You can also use a directory in your home, like `~/bin`, if you have that in your `PATH`).


## How to Use

### Creating a New Commit

1. Make your code changes.

2. Stage your changes as usual:

   ```
   git add .
   ```

   _(or `git add <file1> <file2>...`)_

3. Instead of `git commit`, just run:

   ```
   git commit-auto
   ```

The script will show you the message it generated and then perform the commit.

### Creating and Pushing a New Commit

If you want to create a commit and immediately push it to your remote repository, you can use the `push` command.

1. Make your code changes.
2. Stage your changes:
   ```
   git add .
   ```
3. Run the following command:
   ```
   git commit-auto push
   ```
This will generate the commit message, commit the changes, and then push the commit.

### Regenerating the Last Commit Message

If you are not satisfied with the last commit message, you can easily regenerate it and amend the commit.

1. Make sure you have not pushed the commit yet.
2. Run the following command:
   ```
   git commit-auto regenerate
   ```
This will take the changes from the most recent commit, generate a new message, and amend the commit with the new message.

**Note:** Git automatically recognizes executables in your `PATH` that are named `git-xyz` as Git subcommands. That's why running `git commit-auto` works!
