import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class StatusTimeline extends StatelessWidget {
  final String currentStatus;
  const StatusTimeline({super.key, required this.currentStatus});

  @override
  Widget build(BuildContext context) {
    final steps = [
      'pendiente',
      'asignada',
      'aceptada',
      'en_proceso',
      'finalizada',
    ];
    final currentIndex = steps.indexOf(currentStatus.toLowerCase());
    final displayIndex = currentIndex < 0 ? 0 : currentIndex;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(
          children: List.generate(steps.length, (index) {
            final isCompleted = index <= displayIndex;
            return Expanded(
              child: Column(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    width: isCompleted ? 16 : 12,
                    height: isCompleted ? 16 : 12,
                    decoration: BoxDecoration(
                      color: isCompleted
                          ? AppTheme.primaryBlue
                          : AppTheme.darkBorder,
                      shape: BoxShape.circle,
                      boxShadow: isCompleted
                          ? [
                              BoxShadow(
                                color: AppTheme.primaryBlue.withOpacity(0.4),
                                blurRadius: 8,
                                spreadRadius: 2,
                              ),
                            ]
                          : null,
                    ),
                  ),
                  if (index < steps.length - 1)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      height: 2,
                      color: isCompleted
                          ? AppTheme.primaryBlue
                          : AppTheme.darkBorder,
                    ),
                  const SizedBox(height: 4),
                  Text(
                    steps[index].replaceAll('_', ' ').toUpperCase(),
                    style: TextStyle(
                      fontSize: 8,
                      color: isCompleted
                          ? AppTheme.textPrimary
                          : AppTheme.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }),
        ),
      ],
    );
  }
}
