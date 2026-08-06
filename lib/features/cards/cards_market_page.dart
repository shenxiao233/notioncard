import 'package:flutter/material.dart';

import '../../core/widgets/app_visuals.dart';
import 'cards_page.dart';
import '../market/market_page.dart';

/// Shared entry point for the two content areas that belong to the same
/// workflow: managing personal cards and discovering public decks.
class CardsMarketPage extends StatelessWidget {
  const CardsMarketPage({this.initialTab = 0, super.key});

  final int initialTab;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: initialTab == 1 ? 1 : 0,
      child: Scaffold(
        backgroundColor: AppVisualColors.background,
        body: Column(
          children: [
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '卡片与市场',
                      style: TextStyle(
                        color: AppVisualColors.ink,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '管理你的牌组，也可以发现新的学习内容。',
                      style: TextStyle(
                        color: AppVisualColors.muted,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: appCardShadow,
                      ),
                      child: const TabBar(
                        tabs: [
                          Tab(icon: Icon(Icons.style_outlined), text: '我的卡片'),
                          Tab(
                            icon: Icon(Icons.storefront_outlined),
                            text: '市场',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Expanded(
              child: TabBarView(children: [CardsPage(), MarketPage()]),
            ),
          ],
        ),
      ),
    );
  }
}
