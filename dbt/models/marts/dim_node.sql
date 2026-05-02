{{ config(materialized='table') }}

-- Noeuds du système NAFAD-PAY → mapping AWS eu-west-3
SELECT *
FROM (VALUES
    ('NDB-NODE-1',  'DC-NDB',           'eu-west-3c', 'eu-west-3'),
    ('NDB-NODE-2',  'DC-NDB',           'eu-west-3c', 'eu-west-3'),
    ('NKC-NODE-1',  'DC-NKC-PRIMARY',   'eu-west-3a', 'eu-west-3'),
    ('NKC-NODE-2',  'DC-NKC-PRIMARY',   'eu-west-3a', 'eu-west-3'),
    ('NKC-NODE-3',  'DC-NKC-SECONDARY', 'eu-west-3b', 'eu-west-3')
) AS t(node_id, datacenter, aws_az, aws_region)
