# Focus Mask Feature Demo

## Overview

The Focus Mask creates a full-screen black transparent overlay with a circular cutout around the guide icon, focusing user attention on the setup instructions.

## Features

### 🎭 **Full-Screen Mask**

- **Black Transparent Overlay**: 70% opacity black mask covers entire screen
- **Circular Cutout**: Perfect circle cutout around guide icon
- **Spotlight Effect**: Draws attention to the guide icon

### 🎯 **Circular Cutout**

- **Perfect Circle**: Clean circular opening around guide icon
- **Icon Highlighting**: Guide icon stands out against dark background
- **Professional Look**: Smooth edges with proper masking

### 📱 **Setup Instructions Panel**

- **Right Side Placement**: Instructions displayed on right side of screen
- **Blue Theme**: Consistent with app's color scheme
- **Action Button**: "Open Setup Guide" button for easy access
- **Dismiss Option**: Close button to dismiss the mask

### 🎬 **Animations**

- **Pulse Effect**: Guide icon gently pulses to draw attention
- **Fade Effect**: Instructions panel fades in/out smoothly
- **Smooth Transitions**: Professional animation timing

## How It Works

### **First-Time Users**

1. **Full-Screen Mask**: Black overlay covers entire screen
2. **Circular Cutout**: Guide icon visible through circular opening
3. **Instructions Panel**: Setup guide info displayed on right
4. **Focused Attention**: User's focus drawn to guide icon

### **Returning Users**

1. **No Mask**: Clean interface without overlay
2. **Regular Icon**: Standard guide icon in bottom-left
3. **Quick Access**: One tap to open guide

## Implementation

### **Widget Structure**

```dart
GuideFocusMaskWidget(
  onTap: () => _showConnectionGuide(context),
  onLongPress: () => _resetConnectionGuide(context),
  onDismiss: () => _dismissFocusMask(context),
  iconPosition: Offset(40, 40), // Position relative to bottom-left
  // ... other parameters
)
```

### **Key Components**

- **Full-Screen Container**: Black transparent overlay
- **Custom Painter**: Creates circular cutout effect
- **Positioned Elements**: Guide icon and instructions panel
- **Animation Controllers**: Smooth pulse and fade effects

## User Experience

### **Visual Impact**

- **High Contrast**: Dark mask makes guide icon pop
- **Clear Focus**: Circular cutout eliminates distractions
- **Professional Look**: Smooth animations and clean design

### **Interaction Flow**

1. **See Mask**: Full-screen overlay with circular cutout
2. **Read Instructions**: Setup info displayed on right
3. **Click Icon**: Opens detailed guide dialog
4. **Dismiss Mask**: Tap anywhere or close button
5. **Guide Icon**: Remains for future reference

## Customization

### **Mask Properties**

- **Opacity**: Adjust `Colors.black.withValues(alpha: 0.7)`
- **Cutout Size**: Modify `iconSize + 40` for larger/smaller opening
- **Position**: Change `iconPosition` for different placements

### **Animation Settings**

- **Pulse Duration**: Modify `Duration(seconds: 2)`
- **Scale Range**: Adjust `begin: 1.0, end: 1.1`
- **Fade Range**: Change `begin: 0.8, end: 1.0`

## Testing

### **Reset for Testing**

- **Long Press**: Long press guide icon to reset
- **Mask Returns**: Full-screen overlay reappears
- **Fresh Experience**: Test first-time user flow

### **Dismiss Options**

- **Tap Anywhere**: Tap outside icon to dismiss
- **Close Button**: Use X button in instructions panel
- **State Persistence**: Mask won't show again after dismissal
