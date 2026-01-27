import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'opponent_search_screen.dart';

class MainNavigationShell extends StatefulWidget {
  const MainNavigationShell({super.key});

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  int _selectedIndex = 0;

  // The three main screens of SmashRank
  final List<Widget> _screens = [
    const OpponentSearchScreen(), // Tab 0
    const Center(child: Text('Global Leaderboards (Coming Soon)')), // Tab 1
    const Center(child: Text('My Profile & Stats (Coming Soon)')), // Tab 2
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IndexedStack is key: it keeps screens "alive" in the background
      // so your search results don't disappear when you switch tabs.
      appBar: AppBar(
        title: Text(
          'Quickplay',
          style: GoogleFonts.spaceMono(
            fontWeight: FontWeight.bold,
            fontSize: 24,
          ),
        ),
        backgroundColor: Colors.grey, // Smash Bros theme color
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        selectedItemColor: const Color(0xFFBD0910), // Smash Red
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.search),
            label: 'Find Match',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.leaderboard),
            label: 'Rankings',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
