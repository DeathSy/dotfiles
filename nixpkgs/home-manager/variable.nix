{ pkgs, ... }: {
  home.sessionVariables = {
    ANTHROPIC_API_KEY = "$(pass show claude/personal)";
  };
}
