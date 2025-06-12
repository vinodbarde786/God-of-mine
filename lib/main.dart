import 'package:flutter/material.dart';
import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

void main() {
  runApp(MinesGamePredictor());
}

class MinesGamePredictor extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(primarySwatch: Colors.blue),
      home: MinesPredictorScreen(),
    );
  }
}

class MinesPredictorScreen extends StatefulWidget {
  @override
  _MinesPredictorScreenState createState() => _MinesPredictorScreenState();
}

class _MinesPredictorScreenState extends State<MinesPredictorScreen> {
  final int gridSize = 5; // Fixed 5x5 grid
  int mineCount = 5;
  List<List<bool>> grid = [];
  List<List<bool>> revealed = [];
  List<List<bool>> predictedMines = [];
  List<List<double>> probabilities = [];
  int score = 0;
  bool gameOver = false;
  String predictionMessage = '';
  List<Map<String, dynamic>> gameHistory = [];
  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _loadGameHistory();
    _resetGame();
  }

  Future<void> _loadGameHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyString = prefs.getString('gameHistory') ?? '[]';
    setState(() {
      gameHistory = List<Map<String, dynamic>>.from(jsonDecode(historyString));
    });
  }

  Future<void> _saveGameHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gameHistory', jsonEncode(gameHistory));
  }

  void _resetGame() {
    grid = List.generate(gridSize, () => List.generate(gridSize, () => false));
    revealed = List.generate(gridSize, () => List.generate(gridSize, () => false));
    predictedMines = List.generate(gridSize, () => List.generate(gridSize, () => false));
    probabilities = List.generate(gridSize, () => List.generate(gridSize, () => 0.0));
    _placeMines();
    setState(() {
      gameOver = false;
      score = 0;
      predictionMessage = 'Enter number of mines and click "Predict"!';
    });
  }

  void _placeMines() {
    Random random = Random();
    intint minesPlaced = 0;
    while (minesPlaced < mineCount) {
      int row = random.nextInt(gridSize);
      int col = random.nextInt(gridSize);
      if (!grid[row][col]) {
        grid[row][col] = true;
        minesPlaced++;
      }
    }
  }

  void _predictMines() async {
    if (gameOver) return;
    predictedMines = List.generate(gridSize, () => List.generate(gridSize, () => false));
    probabilities = List.generate(gridSize, () => List.generate(gridSize, () => 0.0));

    // Play prediction sound
    await _audioPlayer.play(AssetSource('sounds/predict.mp3'));

    // Strategy: Prioritize center tiles for mines
    List<Map<String, dynamic>> tiles = [];
    for (int i = 0; i < gridSize; i++) {
      for (int j = 0; j < gridSize; j++) {
        if (!revealed[i][j]) {
          double weight = 1.0;
          double baseProb = mineCount / (gridSize * gridSize - _countRevealedTiles());
          if ((i == 0 && j == 0) || (i == 0 && j == gridSize - 1) ||
              (i == gridSize - 1 && j == 0) || (i == gridSize - 1 && j == gridSize - 1)) {
            weight = 0.5; // Corners
            probabilities[i][j] = baseProb * weight;
          } else if (i == 0 || i == gridSize - 1 || j == 0 || j == gridSize - 1) {
            weight = 0.75; // Edges
            probabilities[i][j] = baseProb * weight;
          } else {
            probabilities[i][j] = baseProb;
          }
          tiles.add({'row': i, 'col': j, 'weight': (weight * Random().nextDouble())});
        }
      }
    }

    // Sort tiles by weight (descending) and select top mineCount tiles
    tiles.sort((a, b) => b['weight'].compareTo(a['weight']));
    List<String> predictedTileNames = [];
    for (int i = 0; i < mineCount && i < tiles.length; i++) {
      int row = tiles[i]['row'];
      int col = tiles[i]['col'];
      predictedMines[row][col] = true;
      predictedTileNames.add('Tile ($row, $col) [${(probabilities[row][col] * 100).toStringAsFixed(1)}%]');
    }

    // Save to game history
    gameHistory.add({
      'mines': mineCount,
      'score': score,
      'predictions': predictedTileNames,
      'timestamp': DateTime.now().toString(),
    });
    await _saveGameHistory();

    setState(() {
      predictionMessage = predictedTileNames.isEmpty
          ? 'No tiles to predict!'
          : 'Predicted mines at: ${predictedTileNames.join(', ')}';
    });
  }

  int _countRevealedTiles() {
    int count = 0;
    for (int i = 0; i < gridSize; i++) {
      for (int j = 0; j < gridSize; j++) {
        if (revealed[i][j]) count++;
      }
    }
    return count;
  }

  void _revealTile(int row, int col) async {
    if (gameOver || revealed[row][col]) return;
    setState(() {
      revealed[row][col] = true;
      if (grid[row][col]) {
        gameOver = true;
        // Play game over sound
        _audioPlayer.play(AssetSource('sounds/game_over.mp3'));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Boom! Mine Found! Game Over!')),
        );
      } else {
        score++;
        // Play safe tile sound
        _audioPlayer.play(AssetSource('sounds/safe.mp3'));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Safe! Score: $score')),
        );
      }
    });
  }

  void _showGameHistory() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Game History'),
        content: SingleChildScrollView(
          child: Column(
            children: gameHistory.map((entry) => ListTile(
              title: Text('Mines: ${entry['mines']} | Score: ${entry['score']}'),
              subtitle: Text('Predictions: ${entry['predictions'].join(', ')}\nTime: ${entry['timestamp']}'),
            )).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Mines Game Predictor'),
        actions: [
          IconButton(
            icon: Icon(Icons.history),
            onPressed: _showGameHistory,
            tooltip: 'Game History',
          ),
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _resetGame,
            tooltip: 'Reset Game',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              decoration: InputDecoration(
                labelText: 'Number of Mines (1-24)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              onChanged: (value) {
                setState(() {
                  mineCount = int.tryParse(value) ?? 5;
                  if (mineCount < 1 || mineCount > 24) mineCount = 5;
                  _resetGame();
                });
              },
            ),
          ),
          Text('Grid: 5x5 | Score: $score', style: TextStyle(fontSize: 20)),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ElevatedButton(
              onPressed: _predictMines,
              child: Text('Predict Mines'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              predictionMessage,
              style: TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: EdgeInsets.all(8),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: gridSize,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemCount: gridSize * gridSize,
              itemBuilder: (context, index) {
                int row = index ~/ gridSize;
                int col = index % gridSize;
                return GestureDetector(
                  onTap: () => _revealTile(row, col),
                  child: AnimatedScale(
                    scale: revealed[row][col] ? 1.0 : (predictedMines[row][col] ? 1.1 : 1.0),
                    duration: Duration(milliseconds: 200),
                    child: Container(
                      decoration: BoxDecoration(
                        color: revealed[row][col]
                            ? (grid[row][col] ? Colors.red : Colors.green)
                            : (predictedMines[row][col] ? Colors.yellow : Colors.grey),
                        border: Border.all(color: Colors.black),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 4,
                            offset: Offset(2, 2),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          revealed[row][col]
                              ? (grid[row][col] ? '💣' : '')
                              : (predictedMines[row][col] ? '⚠️' : ''),
                          style: TextStyle(fontSize: 20),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
