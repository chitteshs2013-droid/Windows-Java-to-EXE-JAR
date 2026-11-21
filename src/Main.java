import javax.swing.*;
import java.awt.*;
import java.awt.event.WindowAdapter;
import java.awt.event.WindowEvent;

public class Main {
    // public and String[] args required for this to work
    public static void main(String[] args) {
        // Basic window
        JFrame window = new JFrame("Hello World");
        window.setLocationRelativeTo(null);
        window.setDefaultCloseOperation(JFrame.DO_NOTHING_ON_CLOSE);
        new Main().setIcon(window);

        window.setResizable(false);
        window.setVisible(true);
    }

    public void setIcon(JFrame window) {
        try {
            java.net.URL iconURL = getClass().getResource("/icon.png");
            if (iconURL != null) {
                Image iconImage = javax.imageio.ImageIO.read(iconURL);
                window.setIconImage(iconImage);
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
}