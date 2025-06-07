# Performance Testing

This directory contains scripts and datasets for testing the performance of the route finder implementation.

## Scripts

- `performance_test.rb` - Main script for running performance tests with different dataset sizes
- `generate_test_data.rb` - Generates test data with ~10k sailings
- `generate_large_dataset.rb` - Generates larger test data with ~250k sailings
- `check_test_data.rb` - Validates the structure of generated test data
- `debug_route_finder.rb` - Helps debug route finder results with detailed output

## Data Files

- `performance_test_data.json` - Medium dataset (10k sailings)
- `massive_performance_test_data.json` - Large dataset (100k sailings)
- `extreme_performance_test_data.json` - Extreme dataset (250k sailings)

## Usage

Run performance tests with:
```
ruby performance_tests/performance_test.rb [1|2|3]
```

Where:
- 1 = Use original small dataset (9 sailings)
- 2 = Use medium dataset (10k sailings)
- 3 = Use extreme dataset (250k sailings)
