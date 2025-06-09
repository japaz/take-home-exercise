# Route Finding Algorithm

## Overview

The application implements a modified version of Dijkstra's shortest path algorithm to find the optimal routes between ports. The algorithm has been enhanced with several optimizations to improve performance and efficiency when dealing with large sets of shipping routes.

## Core Algorithm: Modified Dijkstra's Algorithm

Dijkstra's algorithm is a graph search algorithm that finds the shortest paths between nodes in a graph. In our implementation, ports are nodes, and sailings between ports are edges. The algorithm has been modified to work efficiently for our specific use case of finding optimal shipping routes.

### Key Components

1. **Priority Queue**: The algorithm uses a priority queue to always process the most promising routes first, ensuring that we find optimal solutions efficiently.

2. **Node Structure**: Each node in our implementation tracks:
   - Current port
   - Accumulated cost/time
   - Arrival date
   - Start date
   - Number of path legs
   - Deferred status (for optimization)

3. **Predecessors Map**: Maintains the history of how we reached each port, allowing us to reconstruct the complete route once we reach the destination.

## Optimizations

### 1. Early Termination for Single Destination

Unlike traditional Dijkstra's algorithm that finds shortest paths to all nodes, our implementation terminates as soon as we find the optimal path to the specific destination port. This is implemented by checking if `current_node.port == destination` and stopping exploration along that path.

```ruby
# Check if we've reached the destination.
if current_node.port == destination
  # If we found a better solution, update the best known.
  if is_better_solution?(current_node, best_solution_metric)
    best_solution_metric = current_node.cost
    best_solution = reconstruct_path(predecessors, current_node)
  end
  next
end
```

### 2. Early Pruning

The algorithm avoids exploring paths that are already worse than the current best solution. This pruning technique significantly reduces the search space by abandoning unpromising paths early.

```ruby
# Pruning: If the current path is already worse than our best found solution, skip.
next if current_node.cost >= best_solution_metric
```

### 3. Deferred Processing of Longer Paths

To prioritize exploration of shorter routes first, the algorithm marks longer paths as "deferred" and processes them with lower priority. This ensures that we find direct and short indirect routes before exploring complex multi-leg journeys.

```ruby
# If this is a long route being processed for the first time, mark it as deferred
# and push it back to queue with lower priority (unless it's already marked as deferred)
if tier == :long && !current_node.deferred
  deferred_node = current_node.dup
  deferred_node.deferred = true
  pq.push(deferred_node)
  predecessors[deferred_node] = predecessors[current_node]
  next
end
```

### 4. Cycle Prevention

The algorithm prevents cycles by tracking visited ports and their costs. If we find a better path to a port we've already visited, we update our tracking information. Otherwise, we skip exploring that path, effectively preventing cycles and redundant work.

```ruby
# Skip if we've found a more optimal path to this port
next if next_node.cost >= visited_costs[next_node.port]

# Update visited costs tracker and predecessors
visited_costs[next_node.port] = next_node.cost
```

### 5. Efficient Data Structures

- **Sorted Sailings**: Sailings are pre-sorted by departure date for efficient binary search when finding valid connections.
- **Cost Caching**: Cost calculations for sailings are cached to avoid redundant currency conversions.

```ruby
# bsearch_index is fast (O(log n)) because we pre-sorted the sailings.
start_index = sailings.bsearch_index { |s| s['departure_date_obj'] > current_node.arrival_date }
```

## Strategy Pattern Implementation

The algorithm uses a strategy pattern to enable different optimization criteria (cheapest vs. fastest routes) without duplicating code. This allows easy extension for other route optimization criteria in the future.

## Time Complexity

The time complexity of the algorithm is O((E + V) log V), where:
- E = number of sailings (edges)
- V = number of ports (vertices)

The optimizations reduce the practical runtime significantly by pruning unpromising paths early and prioritizing exploration of the most promising routes.

## Space Complexity

The space complexity is O(V + E) for storing:
- The priority queue (at most V entries)
- Visited costs map (at most V entries)
- Predecessors map (at most E entries)
- Port connections map (proportional to E)

## Limitations

- Performance may degrade with very large datasets or when optimal routes require many legs.

