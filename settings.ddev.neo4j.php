<?php

/**
 * @file
 * #ddev-generated: kevinquillen/ddev-neo4j
 *
 * Neo4j connection block for Drupal sites that consume Neo4j via
 * $settings['content_graph_neo4j'] (or other modules that read the
 * same shape). Included automatically from sites/default/settings.php
 * by the kevinquillen/ddev-neo4j add-on.
 *
 * Re-running `ddev add-on get kevinquillen/ddev-neo4j` will overwrite this
 * file. For non-DDEV environments, define
 * $settings['content_graph_neo4j'] yourself with environment-
 * appropriate credentials.
 */

if (getenv('IS_DDEV_PROJECT') === 'true') {
  $settings['content_graph_neo4j'] = [
    'uri' => 'bolt://neo4j:7687',
    'username' => 'neo4j',
    'password' => getenv('DDEV_NEO4J_PASSWORD') ?: 'ddevpassword',
    'database' => getenv('DDEV_NEO4J_DATABASE') ?: 'neo4j',
  ];
}
