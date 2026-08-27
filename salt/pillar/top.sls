base:
  '*':
    - cluster

  # Secrets are only shipped to the nodes that actually consume them.
  'controller,compute':
    - match: list
    - secrets
