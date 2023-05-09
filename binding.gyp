{
  'targets': [{
    'target_name': 'SwiftFetch.node',
    'type': 'none',
    'actions': [{
      'action_name': 'build.ts',
      'action': [
        'ts-node',
        'scripts/build.ts',
      ],
      'inputs': [],
      'outputs': [
        '<(PRODUCT_DIR)/<(_target_name)',
        '<(PRODUCT_DIR)/nonexistent-file-to-force-rebuild'
      ]
    }]
  }]
}
